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

  it 'a lista do card fechado sai vazia sem ler as execuções' do
    execucao
    card.update!(status: :lost)

    expect(no_card.lista).to eq([])
  end
end
