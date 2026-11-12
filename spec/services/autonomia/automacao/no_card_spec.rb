require 'rails_helper'

# #2499 F6.3: "Parar para este card" no meio de uma rodada. Como no desligar, quem para não registra a execução que está
# andando (o cursor não diz o passo): deixa o porquê nela, e a rodada para sozinha e o registra no passo em que ia.
RSpec.describe Autonomia::Automacao::NoCard, :automacao_motor do
  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:funil_e_etapa) { create_crm_pipeline(account: account, user: admin) }
  let(:card) do
    account.crm_cards.create!(pipeline: funil_e_etapa.first, stage: funil_e_etapa.last, title: 'Pedido', currency: 'BRL')
  end
  let(:definicao) do
    automacao_ligada(account, admin, [esperar_passo('p1')],
                     gatilho: { 'tipo' => 'card.entrou_na_etapa', 'etapa_id' => funil_e_etapa.last.id })
  end
  let(:marca) { Time.current.floor(6) }
  let(:execucao) do
    Autonomia::Automacao::Execucao.create!(account: account, automacao: definicao, versao: definicao.versao_ativa, alvo: card,
                                           chave_gatilho: 'card.entrou_na_etapa', estado: 'andando', travada_em: marca)
  end
  let(:no_card) { described_class.new(card: card, account_user: account.account_users.find_by(user: admin)) }

  before do
    ligar_motor(account)
    account.enable_features!('automacao_gatilhos')
  end

  def registro = Autonomia::Automacao::Registro.find_by(execucao: execucao)

  it 'a rodada que estava andando para e registra que pararam neste card', :aggregate_failures do
    execucao
    expect(no_card.parar!(definicao)).to eq(1)
    expect(registro).to be_nil

    Autonomia::Automacao::Executor.new(execucao.reload, marca).rodar

    expect(execucao.reload.estado).to eq('parada')
    expect(registro).to have_attributes(passo: 'inicio', resultado: 'pulado', motivo: 'parada_no_card')
    expect(definicao.reload.ativa).to be(true)
  end

  it 'a rodada da automação desligada continua registrando "desligada"' do
    execucao
    definicao.desligar!

    Autonomia::Automacao::Executor.new(execucao.reload, marca).rodar

    expect(registro).to have_attributes(resultado: 'pulado', motivo: 'desligada')
  end

  def parada_no_card = Autonomia::Automacao::Registro.where(motivo: 'parada_no_card')

  # Revisão do #2499: o motivo vem do porquê que o parar deixa na execução, nunca de a automação estar ligada.
  it 'o job velho de uma execução que outra rodada já fechou não grava "parada no card"', :aggregate_failures do
    execucao.update!(estado: 'parada')

    Autonomia::Automacao::Executor.new(execucao.reload, marca).rodar

    expect(parada_no_card).to be_empty
    expect(registro).to be_nil
  end

  it 'nem um "desligada" falso quando a automação já está desligada' do
    execucao.update!(estado: 'parada')
    definicao.update!(ativa: false)

    Autonomia::Automacao::Executor.new(execucao.reload, marca).rodar

    expect(registro).to be_nil
  end

  it 'desligar e religar no meio de uma rodada registra "desligada", não "parada no card"' do
    execucao
    definicao.desligar!
    definicao.update!(ativa: true)

    Autonomia::Automacao::Executor.new(execucao.reload, marca).rodar

    expect(registro).to have_attributes(passo: 'inicio', resultado: 'pulado', motivo: 'desligada')
  end

  it 'para a que espera e a que anda numa leitura só: cada uma ganha um registro', :aggregate_failures do
    outro = account.crm_cards.create!(pipeline: funil_e_etapa.first, stage: funil_e_etapa.last, title: 'Outro', currency: 'BRL')
    execucao.update!(estado: 'esperando', cursor: 'p1', travada_em: nil, due_at: 1.hour.from_now)
    paralela = Autonomia::Automacao::Execucao.create!(account: account, automacao: definicao, versao: definicao.versao_ativa,
                                                      alvo: card, chave_gatilho: 'card.entrou_na_etapa', estado: 'andando',
                                                      travada_em: marca, paralela: true)
    de_outro_card = Autonomia::Automacao::Execucao.create!(account: account, automacao: definicao, versao: definicao.versao_ativa,
                                                           alvo: outro, chave_gatilho: 'card.entrou_na_etapa')

    expect(no_card.parar!(definicao)).to eq(2)
    Autonomia::Automacao::Executor.new(paralela.reload, marca).rodar

    expect(parada_no_card.pluck(:execucao_id, :passo)).to contain_exactly([execucao.id, 'p1'], [paralela.id, 'inicio'])
    expect(de_outro_card.reload.estado).to eq('andando')
  end

  # Decisão do Rodrigo (12/11): o "Parar para este card" para também o que a automação começou em outro registro
  # por causa dele (as filhas do passo "em outro registro", achadas pela marca `em:<mãe>:...` do evento).
  describe 'filhas em outro registro' do
    let(:contato) { create(:contact, account: account) }
    let(:outro) { account.crm_cards.create!(pipeline: funil_e_etapa.first, stage: funil_e_etapa.last, title: 'Outro', currency: 'BRL') }

    def filha(mae, alvo, **atributos)
      Autonomia::Automacao::Execucao.create!(account: account, automacao: definicao, versao: definicao.versao_ativa, alvo: alvo,
                                             chave_gatilho: 'card.entrou_na_etapa', estado: 'esperando', cursor: 'p1',
                                             due_at: 1.day.from_now,
                                             evento: Autonomia::Automacao::EmOutroRegistro.marca(mae, alvo, 'p_outro'), **atributos)
    end

    def da_execucao(alvo, **atributos)
      Autonomia::Automacao::Execucao.create!(account: account, automacao: definicao, versao: definicao.versao_ativa, alvo: alvo,
                                             chave_gatilho: 'card.entrou_na_etapa', **atributos)
    end

    it 'a filha aberta é parada com o mesmo motivo; a de outro card e a já terminada não mudam', :aggregate_failures do
      aberta = filha(execucao, contato)
      # Outro contato: só pode haver uma aberta por automação, alvo e gatilho.
      de_outro_card = filha(da_execucao(outro), create(:contact, account: account))
      terminada = filha(execucao, create(:contact, account: account), estado: 'concluida', cursor: nil, due_at: nil)
      terminou_em = terminada.reload.finalizada_em

      expect(no_card.parar!(definicao)).to eq(2)

      expect(execucao.reload.estado).to eq('parada')
      expect(aberta.reload).to have_attributes(estado: 'parada', finalizada_em: be_present)
      expect(parada_no_card.find_by(execucao: aberta)).to have_attributes(passo: 'p1', resultado: 'pulado')
      expect(de_outro_card.reload.estado).to eq('esperando')
      expect(terminada.reload).to have_attributes(estado: 'concluida', finalizada_em: terminou_em)
      expect(parada_no_card.where(execucao: [de_outro_card, terminada])).to be_empty
    end

    it 'a filha da vez que já terminou neste card também para: a mãe não espera as filhas', :aggregate_failures do
      execucao.update!(estado: 'concluida')
      aberta = filha(execucao, contato)

      expect(no_card.parar!(definicao)).to eq(1)
      expect(aberta.reload.estado).to eq('parada')
    end

    it 'a filha que estava no meio de uma rodada para sozinha e registra que pararam neste card', :aggregate_failures do
      execucao.update!(estado: 'esperando', cursor: 'p1', travada_em: nil, due_at: 1.hour.from_now)
      andando = filha(execucao, contato, estado: 'andando', cursor: nil, due_at: nil, travada_em: marca)

      no_card.parar!(definicao)
      Autonomia::Automacao::Executor.new(andando.reload, marca).rodar

      expect(andando.reload.estado).to eq('parada')
      expect(parada_no_card.find_by(execucao: andando)).to have_attributes(resultado: 'pulado')
    end

    it 'a mãe 12 não leva a filha da mãe 123: o ":" depois do id separa as duas' do
      vizinha = Autonomia::Automacao::Execucao.create!(account: account, automacao: definicao, versao: definicao.versao_ativa,
                                                       alvo: contato, chave_gatilho: 'card.entrou_na_etapa', estado: 'esperando',
                                                       cursor: 'p1', due_at: 1.day.from_now,
                                                       evento: "em:#{execucao.id}0:contato:#{contato.id}:p_outro")

      no_card.parar!(definicao)

      expect(vizinha.reload.estado).to eq('esperando')
    end
  end

  it 'a lista do card fechado sai vazia sem ler as execuções' do
    execucao
    card.update!(status: :lost)

    expect(no_card.lista).to eq([])
  end
end
