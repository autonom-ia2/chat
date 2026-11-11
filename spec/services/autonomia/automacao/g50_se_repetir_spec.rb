require 'rails_helper'

# #2414 G50 (#2682, item 2): o gatilho que acontece de novo com a execução ainda aberta no mesmo alvo, e o valor
# `card.entrou_de_novo` da condição do "esperar até". O card anda pelo Crm::Cards::Mover, o evento sai pelo emissor do
# CRM e chega à Partida pelo despacho, como em produção.
RSpec.describe 'Automação livre: o gatilho que se repete (G50)', :automacao_motor do # rubocop:disable RSpec/DescribeClass
  include ActiveJob::TestHelper

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:funil_e_etapa) { create_crm_pipeline(account: account, user: admin, name: 'Alunos') }
  let(:ativo) { funil_e_etapa.last }
  let(:faltou) { create_crm_stage(account: account, pipeline: funil_e_etapa.first, name: 'Faltou', position: 1) }
  let(:card) { account.crm_cards.create!(pipeline: funil_e_etapa.first, stage: ativo, title: 'Lucas', currency: 'BRL') }
  let(:execucoes) { Autonomia::Automacao::Execucao.where(account_id: account.id) }

  before do
    ligar_motor(account)
    account.enable_features!('automacao_gatilhos')
    card
    faltou
    clear_enqueued_jobs
  end

  after { Current.reset }

  def drenar
    drenados = [EventDispatcherJob, Autonomia::Automacao::EventoDoCardJob, Autonomia::Automacao::AvancarJob]
    40.times do
      job = enqueued_jobs.find { |item| drenados.include?(item[:job]) }
      return unless job

      enqueued_jobs.delete(job)
      job[:job].perform_now(*ActiveJob::Arguments.deserialize(job[:args]))
    end
    raise 'a fila não esvaziou em 40 jobs'
  end

  # Só o despacho (EventDispatcherJob) e o evento do card, sem o AvancarJob: a reserva fica visível na fila.
  def despachar_ate_o_evento_do_card
    while (job = enqueued_jobs.find { |item| [EventDispatcherJob, Autonomia::Automacao::EventoDoCardJob].include?(item[:job]) })
      enqueued_jobs.delete(job)
      job[:job].perform_now(*ActiveJob::Arguments.deserialize(job[:args]))
    end
  end

  def mover(etapa)
    Crm::Cards::Mover.new(card: card.reload, actor: admin, target_stage: etapa).perform
    drenar
  end

  def faltou_de_novo
    mover(ativo)
    mover(faltou)
  end

  def gatilho(**extra) = { 'tipo' => 'card.entrou_na_etapa', 'etapa_id' => faltou.id, **extra.transform_keys(&:to_s) }

  def entrou_de_novo(dias = 30)
    { 'id' => 'p10', 'tipo' => 'esperar_ate', 'prazo' => { 'valor' => dias, 'unidade' => 'dias' },
      'condicao' => { 'campo' => { '$valor' => 'card.entrou_de_novo' }, 'op' => 'igual', 'valor' => true } }
  end

  def ligada(passos, **extra) = automacao_ligada(account, admin, passos, gatilho: gatilho(**extra))

  def pulos_ja_aberta = Autonomia::Automacao::Registro.where(account_id: account.id, resultado: 'pulado', motivo: 'ja_aberta')

  describe 'Partida' do
    it 'com se_repetir comeca_outra, a nova entrada abre outra execução, paralela, e nada vira ja_aberta', :aggregate_failures do
      ligada([esperar_passo('p1', 30)], se_repetir: 'comeca_outra')

      mover(faltou)
      faltou_de_novo

      expect(execucoes.abertas.where(alvo: card).count).to eq(2)
      expect(execucoes.pluck(:paralela)).to all(be(true))
      expect(execucoes.pluck(:estado)).to all(eq('esperando'))
      expect(pulos_ja_aberta).to be_empty
    end

    it 'na 3ª entrada nasce a 3ª execução, com as duas primeiras ainda esperando' do
      ligada([esperar_passo('p1', 30)], se_repetir: 'comeca_outra')

      mover(faltou)
      2.times { faltou_de_novo }

      expect(execucoes.abertas.where(alvo: card).count).to eq(3)
    end

    it 'sem se_repetir (o padrão) ou com ignora, a nova entrada não abre outra e fica no histórico como ja_aberta', :aggregate_failures do
      [ligada([esperar_passo('p1', 30)]), ligada([esperar_passo('p1', 30)], se_repetir: 'ignora')]

      mover(faltou)
      faltou_de_novo

      expect(execucoes.abertas.where(alvo: card).count).to eq(2)
      expect(execucoes.pluck(:paralela)).to all(be(false))
      expect(pulos_ja_aberta.count).to eq(2)
    end

    it 'o mesmo evento entregue duas vezes abre uma execução só, também com comeca_outra' do
      definicao = ligada([esperar_passo('p1', 30)], se_repetir: 'comeca_outra')
      partida = lambda do
        Autonomia::Automacao::Partida.new(definicao: definicao, alvo: card, chave_gatilho: 'card.entrou_na_etapa',
                                          evento: 'card.entrou_na_etapa:atividade:42').call
      end

      partida.call
      expect { partida.call }.not_to change(execucoes, :count)
    end

    it 'quem ligou sem permissão pausa a automação também na 2ª entrada', :aggregate_failures do
      definicao = ligada([esperar_passo('p1', 30)], se_repetir: 'comeca_outra')
      mover(faltou)
      agente = create(:user, account: account, role: :agent)
      definicao.update!(ligada_por: agente)

      faltou_de_novo

      expect(definicao.reload.ativa).to be(false)
      expect(Autonomia::Automacao::Registro.where(automacao: definicao).pluck(:motivo)).to include('quem_ligou_sem_permissao')
    end
  end

  describe 'o índice da execução aberta' do
    let(:versao) { ligada([esperar_passo('p1', 30)]).versao_ativa }

    def abrir(paralela)
      create(:autonomia_automacao_execucao, versao: versao, alvo: card, chave_gatilho: 'card.entrou_na_etapa', estado: 'esperando',
                                            paralela: paralela)
    end

    it 'barra a segunda aberta não paralela no mesmo alvo' do
      abrir(false)

      expect { abrir(false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'deixa a paralela ao lado da que está aberta' do
      abrir(false)

      expect { 2.times { abrir(true) } }.to change(execucoes, :count).by(2)
    end
  end

  describe 'salvar' do
    def problemas(receita) = Autonomia::Automacao::Receita.new(receita, conta: account, account_user: nil).problemas
    def frase(chave, **valores) = I18n.t("autonomia.automacao.receita.#{chave}", **valores)

    it 'recusa comeca_outra na mensagem nova e nos gatilhos de tempo', :aggregate_failures do
      passos = [esperar_passo('p1')]
      mensagem = { 'gatilho' => { 'tipo' => 'mensagem.criada', 'se_repetir' => 'comeca_outra' }, 'passos' => passos }
      parado = { 'gatilho' => { 'tipo' => 'card.parado', 'etapa_id' => faltou.id, 'dias' => 3, 'se_repetir' => 'comeca_outra' },
                 'passos' => passos }

      expect(problemas(mensagem)).to include(frase(:se_repetir_fora))
      expect(problemas(parado)).to include(frase(:se_repetir_fora))
      expect(problemas('gatilho' => gatilho(se_repetir: 'comeca_outra'), 'passos' => passos)).to be_empty
    end

    it 'card.entrou_de_novo só na condição do "esperar até" do gatilho de etapa', :aggregate_failures do
      se = { 'id' => 'p1', 'tipo' => 'se', 'condicao' => entrou_de_novo['condicao'], 'entao' => [esperar_passo('p2')] }
      fora = frase(:entrada_so_na_espera, passo: 'p1', caminho: 'card.entrou_de_novo')
      ganho = { 'tipo' => 'card.ganho' }

      expect(problemas('gatilho' => gatilho, 'passos' => [entrou_de_novo])).to be_empty
      expect(problemas('gatilho' => gatilho, 'passos' => [se])).to include(fora)
      expect(problemas('gatilho' => ganho, 'passos' => [entrou_de_novo.merge('id' => 'p1')])).to include(fora)
      expect(problemas('gatilho' => gatilho, 'passos' => [entrou_de_novo.merge('condicao' => entrou_de_novo['condicao'].merge('valor' => 'sim'))]))
        .to include(a_string_including('card.entrou_de_novo'))
    end
  end

  describe 'card.entrou_de_novo' do
    let(:definicao) { ligada([entrou_de_novo, esperar_passo('p11')]) }
    let(:execucao) do
      create(:autonomia_automacao_execucao, versao: definicao.versao_ativa, alvo: card, chave_gatilho: 'card.entrou_na_etapa')
    end

    def lido(espera)
      contexto = Autonomia::Automacao::Contexto.de(card, execucao: execucao)
      Autonomia::Automacao::Valores.new(alvo: contexto, quem: admin, espera: espera).ler('card.entrou_de_novo')
    end

    it 'lê a entrada na etapa do gatilho dentro da janela, mesmo que o card já tenha saído', :aggregate_failures do
      comeco = 1.minute.ago
      mover(faltou)
      mover(ativo)

      expect(card.reload.stage_id).to eq(ativo.id)
      expect(lido(comeco..)).to be(true)
      expect(lido(comeco..1.second.ago.floor)).to be(false)
      expect(lido(Time.current..)).to be(false)
    end

    it 'não conta a entrada em outra etapa, nem sem a janela da espera', :aggregate_failures do
      comeco = 1.minute.ago
      outra = create_crm_stage(account: account, pipeline: funil_e_etapa.first, name: 'Trancou', position: 2)
      mover(outra)

      expect(lido(comeco..)).to be(false)
      mover(faltou)
      expect(lido(nil)).to be(false)
    end
  end

  describe 'o despertar' do
    it 'a nova entrada na etapa acorda na hora o "esperar até" que lê card.entrou_de_novo, e ele segue', :aggregate_failures do
      definicao = ligada([entrou_de_novo, esperar_passo('p11')], se_repetir: 'comeca_outra')
      mover(faltou)
      primeira = execucoes.sole
      expect(primeira).to have_attributes(estado: 'esperando', cursor: 'p10')

      travel(2.days) { faltou_de_novo }

      expect(primeira.reload.cursor).to eq('p11')
      # O primeiro "ok" é o começo da espera; o segundo, a condição cumprida (sem prazo_vencido).
      expect(Autonomia::Automacao::Registro.where(execucao: primeira, passo: 'p10').order(:id).pluck(:resultado, :motivo))
        .to eq([['ok', nil], ['ok', nil]])
      expect(execucoes.where(automacao: definicao).count).to eq(2)
    end

    # Quem acorda é o commit do card (Despertador.card_mudou), com a atividade "move" gravada na mesma transação; o
    # evento da entrada, que chega depois pelo despacho, só abre a 2ª execução e não reserva a 1ª de novo.
    it 'a nova entrada reserva a espera uma vez só, no commit do card', :aggregate_failures do
      ligada([entrou_de_novo, esperar_passo('p11')], se_repetir: 'comeca_outra')
      mover(faltou)
      primeira = execucoes.sole
      avancar_da_primeira = -> { enqueued_jobs.count { |job| job[:job] == Autonomia::Automacao::AvancarJob && job[:args].first == primeira.id } }

      travel(2.days) do
        mover(ativo)
        Crm::Cards::Mover.new(card: card.reload, actor: admin, target_stage: faltou).perform
        expect(primeira.reload.estado).to eq('andando')
        expect(avancar_da_primeira.call).to eq(1)

        despachar_ate_o_evento_do_card
        expect(avancar_da_primeira.call).to eq(1)
        drenar
      end

      expect(primeira.reload.cursor).to eq('p11')
      expect(execucoes.count).to eq(2)
    end

    # G64: a espera com hora marcada só confere nela. A nova entrada na etapa não a acorda, mesmo lendo card.entrou_de_novo.
    it 'não acorda a espera sem prazo com hora marcada (conferir_as) que lê card.entrou_de_novo', :aggregate_failures do
      com_hora = entrou_de_novo.merge('prazo' => 'sem_prazo', 'conferir_as' => 8)
      ligada([com_hora, esperar_passo('p11')], se_repetir: 'comeca_outra')
      mover(faltou)
      primeira = execucoes.sole
      expect(primeira).to have_attributes(estado: 'esperando', cursor: 'p10')

      travel(2.hours) do
        [ativo, faltou].each { |etapa| Crm::Cards::Mover.new(card: card.reload, actor: admin, target_stage: etapa).perform }
        despachar_ate_o_evento_do_card
        expect(primeira.reload.estado).to eq('esperando')
        expect(enqueued_jobs.count { |job| job[:job] == Autonomia::Automacao::AvancarJob && job[:args].first == primeira.id }).to eq(0)
        drenar
      end

      expect(primeira.reload).to have_attributes(estado: 'esperando', cursor: 'p10')
      expect(Autonomia::Automacao::Registro.where(execucao: primeira, passo: 'p10').count).to eq(1)
      expect(execucoes.count).to eq(2)
    end

    # A espera que lê o card (`card.*`) acorda a cada mudança dele pelo Crm::CardAvisaAutomacao (lote 4); a que lê a
    # resposta do cliente não acorda pela nova entrada na etapa.
    it 'não reserva a espera que lê outro valor no mesmo card' do
      resposta = entrou_de_novo.merge('condicao' => { 'campo' => { '$valor' => 'conversa.cliente_respondeu' }, 'op' => 'igual',
                                                      'valor' => true })
      ligada([resposta, esperar_passo('p11')], se_repetir: 'comeca_outra')
      mover(faltou)
      primeira = execucoes.sole

      expect { travel(2.days) { faltou_de_novo } }.not_to(change { primeira.reload.updated_at })
    end
  end
end
