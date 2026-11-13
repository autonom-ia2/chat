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

    # Revisão do #2958: o job que abre as filhas (EmOutroRegistroJob) pode rodar depois do parar, e o parar não desliga
    # a automação. A mãe parada não abre filha nenhuma; sem o parar, a mesma procura abre a filha no outro card.
    describe 'o job das filhas depois do parar' do
      let(:passo) do
        { 'id' => 'p_outro', 'tipo' => 'em_outro_registro', 'registro' => { 'de' => 'cards_do_contato' }, 'passos' => [esperar_passo('r1')] }
      end

      before do
        card.update!(contact: contato)
        outro.update!(contact: contato)
        execucao.update!(estado: 'esperando', cursor: 'p1', travada_em: nil, due_at: 1.hour.from_now)
      end

      def abrir_filhas = Autonomia::Automacao::FilhasDoPasso.new(execucao.reload, passo, contato.id).abrir

      it 'parar no card antes de o job rodar: nenhuma filha nova', :aggregate_failures do
        no_card.parar!(definicao)

        expect { abrir_filhas }.not_to change(Autonomia::Automacao::Execucao, :count)
        expect(execucao.reload.estado).to eq('parada')
      end

      it 'sem o parar, a mesma procura abre a filha no outro card' do
        expect { abrir_filhas }.to change { Autonomia::Automacao::Execucao.where(alvo: outro).count }.by(1)
      end
    end
  end

  # "Cancela tudo" (decisão do Rodrigo, 12/11): o parar fecha também as filhas da lista (`lista:<mãe>:...`), as execuções
  # dos blocos que ela usou (`bloco:<mãe>:...`, de outra automação, no mesmo alvo) e as filhas dessas, por qualquer marca.
  describe 'o que a lista e o bloco começaram' do
    let(:contato) { create(:contact, account: account) }
    let(:outro) { account.crm_cards.create!(pipeline: funil_e_etapa.first, stage: funil_e_etapa.last, title: 'Outro', currency: 'BRL') }
    let(:bloco) do
      create(:autonomia_automacao, account: account, bloco: true).tap do |definicao|
        definicao.salvar_versao!(receita: { 'gatilho' => { 'tipo' => 'card.entrou_na_etapa', 'etapa_id' => funil_e_etapa.last.id },
                                            'passos' => [esperar_passo('b1')] }, autor: admin)
      end
    end

    before { account.enable_features!('automacao_passos_novos') }

    def esperando(automacao, alvo, evento: nil, **atributos)
      Autonomia::Automacao::Execucao.create!(account: account, automacao: automacao, versao: automacao.versao_ativa, alvo: alvo,
                                             chave_gatilho: 'card.entrou_na_etapa', estado: 'esperando', cursor: 'p1',
                                             due_at: 1.day.from_now, evento: evento, **atributos)
    end

    def da_lista(mae, item) = esperando(mae.automacao, item, evento: Autonomia::Automacao::RepetirLista.marca(mae, item, 'p_lista'))

    def do_bloco(mae) = esperando(bloco, mae.alvo, evento: Autonomia::Automacao::Bloco.marca(mae, 'p_bloco', 1), paralela: true)

    it 'a filha da lista aberta para com o mesmo motivo', :aggregate_failures do
      filha = da_lista(execucao, contato)

      expect(no_card.parar!(definicao)).to eq(2)

      expect(filha.reload).to have_attributes(estado: 'parada', finalizada_em: be_present)
      expect(parada_no_card.find_by(execucao: filha)).to have_attributes(passo: 'p1', resultado: 'pulado')
    end

    it 'a execução do bloco que ela usou, de outra automação, para com o mesmo motivo', :aggregate_failures do
      filha = do_bloco(execucao)

      expect(no_card.parar!(definicao)).to eq(2)

      expect(filha.reload.estado).to eq('parada')
      expect(parada_no_card.find_by(execucao: filha)).to have_attributes(passo: 'p1', resultado: 'pulado')
    end

    it 'as netas também param: o bloco que a filha da lista usou e o "em outro registro" do bloco', :aggregate_failures do
      neta_da_lista = do_bloco(da_lista(execucao, contato))
      bloco_do_card = do_bloco(execucao)
      indicado = create(:contact, account: account)
      neta_do_bloco = esperando(bloco, indicado, evento: Autonomia::Automacao::EmOutroRegistro.marca(bloco_do_card, indicado, 'p_outro'))

      expect(no_card.parar!(definicao)).to eq(5)

      expect([neta_da_lista, bloco_do_card, neta_do_bloco].map { |uma| uma.reload.estado }).to all(eq('parada'))
    end

    it 'o que nasceu de outro card, ou de outra automação neste card, não muda', :aggregate_failures do
      execucao
      de_outro_card = esperando(definicao, outro)
      outra_automacao = automacao_ligada(account, admin, [esperar_passo('p1')],
                                         gatilho: { 'tipo' => 'card.entrou_na_etapa', 'etapa_id' => funil_e_etapa.last.id })
      da_outra_automacao = esperando(outra_automacao, card)
      intactas = [de_outro_card, do_bloco(de_outro_card), da_lista(de_outro_card, contato), da_outra_automacao, do_bloco(da_outra_automacao)]

      expect(no_card.parar!(definicao)).to eq(1)

      expect(intactas.map { |uma| uma.reload.estado }).to all(eq('esperando'))
      expect(parada_no_card.where(execucao: intactas)).to be_empty
    end

    # Como no FilhasDoPasso: o RepetirListaJob pode rodar depois do parar, e o parar não desliga a automação. A mãe
    # parada não abre filha nenhuma; sem o parar, a mesma lista abre a filha do contato.
    describe 'o job da lista depois do parar' do
      let(:passo) do
        { 'id' => 'p_lista', 'tipo' => 'repetir_lista', 'lista' => { 'de' => 'etiqueta', 'etiqueta' => 'vip' }, 'teto' => 2,
          'ritmo' => 'rapido', 'cada' => [esperar_passo('c1')] }
      end

      before do
        account.labels.create!(title: 'vip')
        contato.update!(label_list: ['vip'])
        execucao.update!(estado: 'esperando', cursor: 'p1', travada_em: nil, due_at: 1.hour.from_now)
      end

      def abrir_filhas = Autonomia::Automacao::FilhasDaLista.new(execucao.reload, passo).abrir

      it 'parar no card antes de o job rodar: nenhuma filha nova e nenhuma linha no histórico da mãe', :aggregate_failures do
        no_card.parar!(definicao)

        expect { expect(abrir_filhas).to eq('mae_parada' => 1) }.not_to change(Autonomia::Automacao::Execucao, :count)
        expect(Autonomia::Automacao::Registro.where(execucao: execucao, passo: 'p_lista')).to be_empty
      end

      it 'sem o parar, a mesma lista abre a filha do contato' do
        expect { abrir_filhas }.to change { Autonomia::Automacao::Execucao.where(alvo: contato).count }.by(1)
      end
    end
  end

  it 'a lista do card fechado sai vazia sem ler as execuções' do
    execucao
    card.update!(status: :lost)

    expect(no_card.lista).to eq([])
  end
end
