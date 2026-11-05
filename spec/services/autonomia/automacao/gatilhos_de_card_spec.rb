require 'rails_helper'

# #2499 (F6): os gatilhos de card. O card criado, movido, ganho ou perdido sai pelo emissor do CRM, chega à escuta pelo
# despacho assíncrono e começa as automações ligadas com o gatilho, na etapa ou no funil escolhidos. Tudo passa pela
# plataforma: a atividade grava, o emissor despacha, o EventDispatcherJob entrega, a Partida abre e o AvancarJob roda.
RSpec.describe 'Automação livre: gatilhos de card', :automacao_motor do # rubocop:disable RSpec/DescribeClass
  include ActiveJob::TestHelper

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:funil_e_etapa) { create_crm_pipeline(account: account, user: admin) }
  let(:funil) { funil_e_etapa.first }
  let(:novo) { funil_e_etapa.last }
  let(:proposta) { create_crm_stage(account: account, pipeline: funil, name: 'Proposta', position: 1) }
  let(:fechamento) { create_crm_stage(account: account, pipeline: funil, name: 'Fechamento', position: 2) }
  let(:conversa) { create(:conversation, account: account, status: :open) }
  let(:card) do
    account.crm_cards.create!(pipeline: funil, stage: novo, title: 'Pedido', currency: 'BRL', primary_conversation: conversa,
                              contact: conversa.contact)
  end
  let(:execucoes) { Autonomia::Automacao::Execucao }
  let(:cadeia) { Autonomia::Automacao::Cadeia }

  before do
    ligar_motor(account)
    account.enable_features!('automacao_gatilhos')
    card
    proposta
    fechamento
    clear_enqueued_jobs
  end

  after { Current.reset }

  # Um job de cada vez, na ordem da fila: o job enfileirado dentro de outro só roda depois dele.
  def drenar
    drenados = [EventDispatcherJob, Autonomia::Automacao::AvancarJob]
    40.times do
      job = enqueued_jobs.find { |item| drenados.include?(item[:job]) }
      return unless job

      enqueued_jobs.delete(job)
      job[:job].perform_now(*ActiveJob::Arguments.deserialize(job[:args]))
    end
    raise 'a fila não esvaziou em 40 jobs'
  end

  def mover_passo(id, etapa)
    { 'id' => id, 'tipo' => 'acao', 'acao' => 'POST crm/cards/:id/move', 'descricao' => 'Mover o card',
      'caminho' => { 'id' => { '$valor' => 'card.id' } }, 'corpo' => { 'stage_id' => etapa.id } }
  end

  def de_card(tipo, passos = [esperar_passo('p1')], **parametros)
    automacao_ligada(account, admin, passos, gatilho: { 'tipo' => tipo, **parametros.transform_keys(&:to_s) })
  end

  def mover(alvo, etapa) = Crm::Cards::Mover.new(card: alvo, actor: admin, target_stage: etapa).perform

  def recusas(motivo) = have_received(:registrar_recusa).with(having_attributes(motivo: motivo), any_args)

  describe 'o evento começa a automação do gatilho' do
    it 'mover dispara "saiu" da etapa de origem e "entrou" na de destino, só nas etapas escolhidas', :aggregate_failures do
      saiu_do_novo = de_card('card.saiu_da_etapa', etapa_id: novo.id)
      entrou_na_proposta = de_card('card.entrou_na_etapa', etapa_id: proposta.id)
      entrou_no_fechamento = de_card('card.entrou_na_etapa', etapa_id: fechamento.id)

      mover(card, proposta)
      drenar

      expect(execucoes.where(automacao: [saiu_do_novo, entrou_na_proposta]).pluck(:chave_gatilho))
        .to contain_exactly('card.saiu_da_etapa', 'card.entrou_na_etapa')
      expect(execucoes.where(automacao: entrou_no_fechamento)).to be_empty
      expect(execucoes.where(automacao: entrou_na_proposta).sole).to have_attributes(alvo: card)
    end

    it 'o card criado dispara "criado" e "entrou" na etapa em que nasceu', :aggregate_failures do
      criado = de_card('card.criado')
      criado_noutro_funil = de_card('card.criado', funil_id: create_crm_pipeline(account: account, user: admin, name: 'Outro').first.id)
      entrou = de_card('card.entrou_na_etapa', etapa_id: proposta.id)

      novo_card = Crm::Cards::Creator.new(account: account, user: admin,
                                          params: { pipeline_id: funil.id, stage_id: proposta.id, title: 'Novo', currency: 'BRL' }).perform
      drenar

      expect(execucoes.where(automacao: [criado, entrou]).pluck(:alvo_id)).to eq([novo_card.id, novo_card.id])
      expect(execucoes.where(automacao: criado_noutro_funil)).to be_empty
    end

    it 'ganho e perdido, no funil escolhido', :aggregate_failures do
      ganho = de_card('card.ganho', funil_id: funil.id)
      perdido = de_card('card.perdido')

      Crm::Cards::Closer.new(card: card, actor: admin, result: 'won').perform
      drenar

      expect(execucoes.where(automacao: ganho).count).to eq(1)
      expect(execucoes.where(automacao: perdido)).to be_empty
    end

    # O EventDispatcherJob repete o evento: a marca da atividade barra a segunda execução, mesmo com a primeira fechada.
    it 'o mesmo evento entregue 2 vezes abre 1 execução', :aggregate_failures do
      definicao = de_card('card.entrou_na_etapa', etapa_id: proposta.id)
      mover(card, proposta)
      atividade = Crm::Activity.where(card: card, event_type: 'move').sole
      dados = { account_id: account.id, card_id: card.id, activity_id: atividade.id, changed_attributes: atividade.payload }

      Autonomia::Automacao::Escuta.evento_do_card(dados, Events::Types::CRM_CARD_MOVED)
      execucoes.update_all(estado: 'concluida', travada_em: nil, due_at: nil, finalizada_em: Time.current) # rubocop:disable Rails/SkipsModelValidations
      Autonomia::Automacao::Escuta.evento_do_card(dados, Events::Types::CRM_CARD_MOVED)

      expect(execucoes.where(automacao: definicao).sole.evento).to eq("card.entrou_na_etapa:atividade:#{atividade.id}")
    end

    it 'os valores do card, da conversa principal e do contato entram no filtro do gatilho' do
      do_valor = de_card('card.entrou_na_etapa', etapa_id: proposta.id).tap do |definicao|
        receita = definicao.versao_ativa.receita.deep_dup
        receita['gatilho']['filtros'] = [{ 'campo' => { '$valor' => 'card.titulo' }, 'op' => 'igual', 'valor' => 'Outro' }]
        definicao.salvar_versao!(receita: receita, autor: admin)
        definicao.update!(ativa: true)
      end

      mover(card, proposta)
      drenar

      expect(execucoes.where(automacao: do_valor)).to be_empty
    end
  end

  # A regra do Rodrigo: até 3 níveis, nunca a si mesma.
  describe 'laço e cascata' do
    before { allow(cadeia).to receive(:registrar_recusa).and_call_original }

    it 'a automação que leva o card de volta à etapa do próprio gatilho roda uma vez: a volta é auto-disparo', :aggregate_failures do
      definicao = de_card('card.entrou_na_etapa', [mover_passo('a1', novo), mover_passo('a2', proposta)], etapa_id: proposta.id)

      mover(card, proposta)
      drenar

      expect(execucoes.where(automacao: definicao).pluck(:estado)).to eq(['concluida'])
      expect(cadeia).to recusas(:auto_disparo)
      expect(card.reload.stage).to eq(proposta)
    end

    it 'uma cascata de automações diferentes para no 3º nível', :aggregate_failures do
      mais = (3..5).map { |posicao| create_crm_stage(account: account, pipeline: funil, name: "E#{posicao}", position: posicao) }
      etapas = [proposta, fechamento, *mais]
      cascata = etapas.each_cons(2).map.with_index do |(de, para), indice|
        de_card('card.entrou_na_etapa', [mover_passo("c#{indice}", para)], etapa_id: de.id)
      end
      clear_enqueued_jobs

      mover(card, proposta)
      drenar

      expect(cascata.map { |definicao| execucoes.where(automacao: definicao).count }).to eq([1, 1, 1, 0])
      expect(cadeia).to recusas(:profundidade)
      expect(card.reload.stage).to eq(etapas[3])
    end
  end

  describe 'a flag e a permissão' do
    it 'sem a flag, o emissor não despacha e nada começa', :aggregate_failures do
      de_card('card.entrou_na_etapa', etapa_id: proposta.id)
      account.disable_features!('automacao_gatilhos')

      mover(card, proposta)

      expect(enqueued_jobs.map { |job| job[:job] }).not_to include(EventDispatcherJob)
      drenar
      expect(execucoes.count).to eq(0)
    end

    it 'a flag desligada no meio fecha como parada a execução aberta de gatilho de card', :aggregate_failures do
      definicao = de_card('card.entrou_na_etapa', [esperar_passo('p1'), mover_passo('p2', fechamento)], etapa_id: proposta.id)
      mover(card, proposta)
      drenar
      account.disable_features!('automacao_gatilhos')

      travel(2.days) { varrer }

      expect(execucoes.where(automacao: definicao).sole).to have_attributes(estado: 'parada')
      expect(Autonomia::Automacao::Registro.where(automacao: definicao).last.motivo).to eq('gatilho_desligado')
      expect(card.reload.stage).to eq(proposta)
    end

    # A função tem a chave de automações e enxerga os cards, mas não a de funis: o gatilho de card pede as duas.
    it 'quem ligou sem a chave de funis pausa a automação com sem_permissao_funil', :aggregate_failures do
      agente = create(:user, account: account, role: :agent)
      funcao = create(:custom_role, account: account, permissions: %w[automation_manage conversation_manage crm_view crm_manage_cards])
      account.account_users.find_by(user: agente).update!(custom_role: funcao)
      definicao = de_card('card.entrou_na_etapa', etapa_id: proposta.id)
      definicao.update!(ligada_por: agente)

      mover(card, proposta)
      drenar

      expect(definicao.reload.ativa).to be(false)
      expect(Autonomia::Automacao::Registro.where(automacao: definicao).sole.motivo).to eq('sem_permissao_funil')
    end
  end

  describe 'o gate do emissor' do
    it 'conta só com automação despacha, mas não chama webhook nem Meta nem Google', :aggregate_failures do
      de_card('card.entrou_na_etapa', etapa_id: proposta.id)

      mover(card, proposta)
      perform_enqueued_jobs(only: EventDispatcherJob)

      fora = [Webhooks::CrmDeliveryJob, WebhookJob, Crm::MetaCapi::DispatchJob, Crm::GoogleOffline::RecordJob]
      expect(enqueued_jobs.map { |job| job[:job] } & fora).to be_empty
      expect(execucoes.count).to eq(1)
    end

    it 'conta com a flag mas sem automação de card não despacha' do
      de_card('card.ganho')

      mover(card, proposta)

      expect(enqueued_jobs.map { |job| job[:job] }).not_to include(EventDispatcherJob)
    end
  end
end
