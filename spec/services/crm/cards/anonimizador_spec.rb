require 'rails_helper'

# LGPD (#2096, decisão 1): o contato excluído deixa os cards sem dado pessoal. Um card com o mesmo marcador em todo
# lugar onde texto ou dado da pessoa pode morar; depois de excluir o contato (e rodar as exclusões em segundo plano das
# conversas), o marcador não pode aparecer em nenhuma tabela do banco. Valor, funil, etapa, status, desfecho e datas
# continuam lá.
RSpec.describe Crm::Cards::Anonimizador do
  include ActiveJob::TestHelper

  let(:marcador) { 'DADO-PESSOAL-XYZ' }
  let(:account) { create(:account, locale: 'pt_BR') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
  let(:pipeline) { pipeline_and_stage.first }
  let(:stage) { pipeline_and_stage.last }
  let(:proposta) { create_crm_stage(account: account, pipeline: pipeline, name: 'Proposta') }
  let(:contact) do
    account.contacts.create!(name: "Cliente #{marcador}", phone_number: '+5511999990031', email: "#{marcador.downcase}@example.com")
  end
  let(:inbox) { create_crm_inbox(account: account) }
  let(:conversation) { create_crm_conversation(account: account, inbox: inbox, contact: contact) }
  let(:closed_at) { 3.days.ago.change(usec: 0) }

  before { account.enable_features!(:crm_arquivados) }

  # Onde o marcador ainda aparece: toda tabela do banco, linha inteira como texto.
  def onde_o_marcador_aparece
    conexao = ActiveRecord::Base.connection
    padrao = conexao.quote("%#{marcador}%")
    conexao.tables.select do |tabela|
      nome = conexao.quote_table_name(tabela)
      conexao.select_value("SELECT 1 FROM #{nome} AS t WHERE t::text ILIKE #{padrao} LIMIT 1").present?
    end
  end

  # rubocop:disable Metrics/AbcSize
  def card_com_dado_pessoal
    card = account.crm_cards.create!(pipeline: pipeline, stage: proposta, contact: contact, conversation_id: conversation.id,
                                     title: 'Pedido', value_cents: 150_000, currency: 'BRL', status: :open)
    card.update_columns(title: "Pedido #{marcador}", description: marcador, lost_reason: marcador, source: marcador, # rubocop:disable Rails/SkipsModelValidations
                        external_id: marcador, custom_attributes: { 'cpf' => marcador }, status: Crm::Card.statuses[:archived],
                        closed_at: closed_at, next_follow_up_at: 1.day.from_now,
                        metadata: { 'livre' => marcador, 'desfecho_arquivado' => 'won',
                                    'ai' => { 'summary' => marcador, 'score' => { 'reason' => marcador } },
                                    'autonomia_prospecting' => { 'summary' => marcador } })
    Crm::CardConversation.create!(account: account, card: card, conversation: conversation)
    card
  end
  # rubocop:enable Metrics/AbcSize

  def atividades_com_texto(card)
    [
      ['note', { 'text' => marcador }],
      ['move', { 'from_stage_id' => stage.id, 'to_stage_id' => proposta.id }],
      ['won', { 'value_cents' => 150_000, 'currency' => 'BRL', 'lost_reason' => marcador,
                'closed_with' => { 'responsible' => { 'type' => 'agent', 'id' => admin.id, 'name' => 'Atendente' } } }],
      ['ai_subject_opened', { 'acao' => 'abrir', 'motivo' => marcador, 'resumo' => marcador, 'pedido_por' => marcador }],
      ['ai_handoff', { 'mode' => 'invite', 'reason' => marcador }],
      ['update', { 'title' => marcador, 'custom_attributes' => { 'cpf' => marcador }, 'value_cents' => 150_000 }]
    ].each do |event_type, payload|
      Crm::ActivityLogger.new(card: card, actor: admin, event_type: event_type, payload: payload, conversation: conversation).perform
    end
  end

  def retornos_com_texto(card)
    Crm::FollowUp.create!(account: account, card: card, contact: contact, conversation: conversation, title: "Ligar #{marcador}",
                          description: marcador, due_at: 1.day.from_now, status: :pending,
                          metadata: { 'message_body' => marcador, 'source' => 'manual' })
    Crm::FollowUp.create!(account: account, card: card, title: "Feito #{marcador}", due_at: 2.days.ago, status: :done)
    Crm::FollowUpSeries.create!(account: account, card: card, contact: contact, title: marcador, description: marcador,
                                frequency: :daily, starts_at: 1.day.from_now, timezone: 'UTC', metadata: { 'nota' => marcador })
  end

  # rubocop:disable Metrics/AbcSize
  def reunioes_com_texto(card)
    futura = create_reuniao(account: account, card: card, user: admin, contact: contact, starts_at: 2.days.from_now)
    futura.update!(title: "Reunião #{marcador}", description: marcador)
    passada = create_reuniao(account: account, card: card, user: admin, contact: contact, starts_at: 5.days.ago)
    passada.update_columns(title: marcador, description: marcador, outcome_notes: marcador, status: Crm::Meeting.statuses[:completed], # rubocop:disable Rails/SkipsModelValidations
                           online_meeting_url: "https://meet.example.com/#{marcador}",
                           metadata: { 'ai_summary' => marcador, 'location' => marcador, 'booking_profile_id' => 7, 'test' => false })
    passada.meeting_guests.create!(account: account, email: 'acompanhante@example.com', name: marcador, guest_type: :external_email)
    passada.meeting_guests.create!(account: account, user: admin, email: admin.email, name: admin.name, guest_type: :internal_user)
    [futura, passada]
  end
  # rubocop:enable Metrics/AbcSize

  # rubocop:disable Metrics/AbcSize
  def ia_e_vinculos_com_texto(card)
    account.crm_ai_stage_suggestions.create!(card: card, from_stage: stage, to_stage: proposta, confidence: 0.8, reasoning: marcador,
                                             model_used: 'm', metadata: { 'fechar' => { 'motivo' => marcador } })
    Crm::Memoria::Gravador.gravar!(account_id: account.id, contact_id: contact.id, escopo: 'card', card_id: card.id, tipo: 'fato',
                                   chave: 'placa', valor: marcador, fonte: 'pessoa_corrigiu', gerado_por: 'spec')
    automacao = account.crm_stage_automations.create!(pipeline: pipeline, stage: proposta, name: 'Boas-vindas', trigger_event: :on_enter)
    Crm::StageAutomationExecution.create!(account: account, card: card, stage_automation: automacao, trigger_token: 'tk',
                                          error_message: marcador, metadata: { 'step_results' => [{ 'error' => marcador }] })
    Crm::SubjectDecision.create!(account: account, conversation: conversation, mode: 'suggest', action: 'create', state: 'suggested',
                                 pipeline: pipeline, card: card, title: marcador, reason: marcador, touched_card_ids: [card.id])
    create(:autonomia_decisor_decisao, account: account, decisor: create(:autonomia_decisor, account: account),
                                       conversation: conversation, message: nil, crm_card_id: card.id,
                                       campos_extraidos: { 'cpf' => marcador }, motivo: marcador)
    create(:crm_google_conversion_event, account: account, card_id: card.id, gclid: marcador, status: 'ready')
    Crm::MetaConversionEvent.create!(account: account, card: card, event_id: "crm-#{card.id}-won-1", event_type: 'won',
                                     status: :pending, ctwa_clid: marcador, value_cents: 150_000, currency: 'BRL')
  end
  # rubocop:enable Metrics/AbcSize

  def excluir_o_contato
    perform_enqueued_jobs(only: ActiveRecord::DestroyAssociationAsyncJob) { contact.destroy! }
  end

  describe 'contato excluído com um card cheio de dado pessoal' do
    let!(:card) do
      card_com_dado_pessoal.tap do |novo|
        atividades_com_texto(novo)
        retornos_com_texto(novo)
        ia_e_vinculos_com_texto(novo)
      end
    end
    let!(:reunioes) { reunioes_com_texto(card) }

    it 'tem o marcador no card, no histórico e no contato antes (a busca funciona)' do
      expect(onde_o_marcador_aparece).to include('crm_cards', 'crm_activities', 'crm_follow_ups', 'crm_meetings', 'crm_memoria_fatos',
                                                 'crm_ai_stage_suggestions', 'autonomia_decisor_decisoes', 'contacts')
    end

    context 'when o contato é excluído' do
      before do
        excluir_o_contato
        card.reload
      end

      it 'não sobra o marcador em nenhuma tabela do banco' do
        expect(onde_o_marcador_aparece).to eq([])
      end

      it 'o card vira "Cliente removido #id" e mantém valor, funil, etapa, status, desfecho e datas' do
        expect(card.title).to eq("Cliente removido ##{card.id}")
        expect(card.attributes.slice('pipeline_id', 'stage_id', 'status', 'value_cents', 'currency', 'closed_at'))
          .to eq('pipeline_id' => pipeline.id, 'stage_id' => proposta.id, 'status' => 'archived', 'value_cents' => 150_000,
                 'currency' => 'BRL', 'closed_at' => closed_at)
        expect(card.metadata.keys).to contain_exactly('desfecho_arquivado', 'contato_removido_em')
        expect(card.metadata['desfecho_arquivado']).to eq('won')
      end

      it 'o card perde o contato, a conversa e todo campo de texto' do
        expect(card.attributes.slice('contact_id', 'conversation_id', 'description', 'lost_reason', 'source', 'external_id',
                                     'custom_attributes', 'next_follow_up_at'))
          .to eq('contact_id' => nil, 'conversation_id' => nil, 'description' => nil, 'lost_reason' => nil, 'source' => nil,
                 'external_id' => nil, 'custom_attributes' => {}, 'next_follow_up_at' => nil)
        expect(Crm::CardConversation.where(card_id: card.id)).to be_empty
      end

      it 'o histórico que conta fica, sem texto e sem a conversa' do
        expect(card.activities.find_by(event_type: 'move').payload).to eq('from_stage_id' => stage.id, 'to_stage_id' => proposta.id)
        expect(card.activities.find_by(event_type: 'won').payload)
          .to eq('value_cents' => 150_000, 'currency' => 'BRL',
                 'closed_with' => { 'responsible' => { 'type' => 'agent', 'id' => admin.id, 'name' => 'Atendente' } })
        expect(card.activities.where.not(conversation_id: nil)).to be_empty
        expect(card.activities.count).to eq(7)
      end

      it 'a reunião futura é cancelada e a passada fica sem texto, só com o atendente convidado' do
        futura, passada = reunioes.map(&:reload)
        expect([futura.status, passada.status, passada.outcome_notes, passada.online_meeting_url]).to eq(['canceled', 'completed', nil, nil])
        expect(passada.metadata).to eq('booking_profile_id' => 7, 'test' => false)
        expect(passada.meeting_guests.pluck(:guest_type)).to eq(['internal_user'])
      end

      it 'o retorno pendente é cancelado, o feito fica, a série acaba, todos sem texto' do
        expect(card.follow_ups.order(:due_at).pluck(:status, :title)).to eq([['done', 'Cliente removido'], ['canceled', 'Cliente removido']])
        expect(card.follow_ups.order(:due_at).last.metadata).to eq('source' => 'manual', 'canceled_reason' => 'contact_removed')
        expect(Crm::FollowUpSeries.find_by(card_id: card.id).attributes.slice('status', 'description'))
          .to eq('status' => 'ended', 'description' => nil)
      end

      it 'a conversão fica sem o clique e não é mais enviada; decisões do decisor saem' do
        expect(Crm::GoogleConversionEvent.find_by(card_id: card.id).attributes.slice('status', 'skip_reason', 'gclid'))
          .to eq('status' => 'skipped', 'skip_reason' => 'contact_removed', 'gclid' => nil)
        expect(Crm::MetaConversionEvent.find_by(card_id: card.id).attributes.slice('status', 'ctwa_clid'))
          .to eq('status' => 'skipped', 'ctwa_clid' => nil)
        expect(Autonomia::DecisorDecisao.where(crm_card_id: card.id)).to be_empty
      end
    end
  end

  it 'anonimiza os cards abertos, ganhos e arquivados do contato e não toca o card de outro contato' do
    outro = account.contacts.create!(name: 'Outra pessoa', phone_number: '+5511999990032')
    aberto = account.crm_cards.create!(pipeline: pipeline, stage: stage, contact: contact, title: 'Aberto', status: :open)
    ganho = account.crm_cards.create!(pipeline: pipeline, stage: stage, contact: contact, title: 'Ganho', status: :won, value_cents: 9_000)
    alheio = account.crm_cards.create!(pipeline: pipeline, stage: stage, contact: outro, title: 'Alheio', status: :open)

    expect(described_class.new(contact: contact).perform).to eq([aberto.id, ganho.id])

    expect([aberto.reload.title, ganho.reload.title]).to eq(["Cliente removido ##{aberto.id}", "Cliente removido ##{ganho.id}"])
    expect([aberto.status, ganho.status, ganho.value_cents]).to eq(['open', 'won', 9_000])
    expect(alheio.reload.attributes.slice('title', 'contact_id')).to eq('title' => 'Alheio', 'contact_id' => outro.id)
  end

  it 'na mesclagem, os cards vão para o contato que fica, com título e dados' do
    card = account.crm_cards.create!(pipeline: pipeline, stage: stage, contact: contact, title: 'Pedido do absorvido', status: :open,
                                     description: 'detalhe', custom_attributes: { 'placa' => 'ABC' })
    base = account.contacts.create!(name: 'Quem fica', phone_number: '+5511999990033')

    ContactMergeAction.new(account: account, base_contact: base, mergee_contact: contact).perform

    expect(Contact.exists?(contact.id)).to be(false)
    expect(card.reload.attributes.slice('contact_id', 'title', 'description', 'custom_attributes'))
      .to eq('contact_id' => base.id, 'title' => 'Pedido do absorvido', 'description' => 'detalhe', 'custom_attributes' => { 'placa' => 'ABC' })
    expect(card.metadata).not_to have_key('contato_removido_em')
  end

  it 'não exclui o contato nem limpa nada quando a reunião futura não cancela no calendário' do
    card = account.crm_cards.create!(pipeline: pipeline, stage: stage, contact: contact, title: 'Pedido', status: :open)
    create_reuniao(account: account, card: card, user: admin, contact: contact, starts_at: 2.days.from_now)
    servico = instance_double(Crm::Meetings::CancelService)
    allow(servico).to receive(:perform).and_raise(Net::ReadTimeout)
    allow(Crm::Meetings::CancelService).to receive(:new).and_return(servico)

    expect { contact.destroy! }.to raise_error(Crm::ExclusaoDefinitiva::ReuniaoNaoCancelada)

    expect(Contact.exists?(contact.id)).to be(true)
    expect(card.reload.attributes.slice('title', 'contact_id')).to eq('title' => 'Pedido', 'contact_id' => contact.id)
  end

  it 'na exclusão em lote, mantém inteiro o contato cuja reunião não cancela e exclui os outros' do
    preso = account.crm_cards.create!(pipeline: pipeline, stage: stage, contact: contact, title: 'Preso', status: :open)
    create_reuniao(account: account, card: preso, user: admin, contact: contact, starts_at: 2.days.from_now)
    outro = account.contacts.create!(name: 'Outro', phone_number: '+5511999990034')
    livre = account.crm_cards.create!(pipeline: pipeline, stage: stage, contact: outro, title: 'Livre', status: :open)
    servico = instance_double(Crm::Meetings::CancelService)
    allow(servico).to receive(:perform).and_raise(Errno::ECONNREFUSED)
    allow(Crm::Meetings::CancelService).to receive(:new).and_return(servico)

    Contacts::BulkDeleteService.new(account: account, contact_ids: [contact.id, outro.id]).perform

    expect([Contact.exists?(contact.id), Contact.exists?(outro.id)]).to eq([true, false])
    expect([preso.reload.title, livre.reload.title]).to eq(['Preso', "Cliente removido ##{livre.id}"])
  end

  # Uma reunião marcada entre o cancelamento e a trava ficaria com o convite num card sem cliente.
  it 'não limpa nada quando, sob a trava, ainda há reunião futura marcada' do
    card = account.crm_cards.create!(pipeline: pipeline, stage: stage, contact: contact, title: 'Pedido', status: :open)
    reuniao = create_reuniao(account: account, card: card, user: admin, contact: contact, starts_at: 2.days.from_now)
    allow(Crm::Meetings::CancelarFuturas).to receive(:new).and_return(instance_double(Crm::Meetings::CancelarFuturas, perform: [], so_aqui: []))

    expect { contact.destroy! }.to raise_error(Crm::ExclusaoDefinitiva::Mudou) { |erro| expect(erro.motivo).to eq('cards_changed') }

    expect([Contact.exists?(contact.id), card.reload.title, reuniao.reload.status]).to eq([true, 'Pedido', 'scheduled'])
  end

  it 'na exclusão em lote, um contato que falha por qualquer motivo não derruba o lote, e a falha fica registrada' do
    preso = account.crm_cards.create!(pipeline: pipeline, stage: stage, contact: contact, title: 'Preso', status: :open)
    outro = account.contacts.create!(name: 'Outro', phone_number: '+5511999990035')
    falho = instance_double(described_class, cancelar_reunioes!: [], reunioes_canceladas: [])
    allow(falho).to receive(:perform).and_raise(ActiveRecord::Deadlocked)
    allow(described_class).to receive(:new).and_call_original
    allow(described_class).to receive(:new).with(contact: contact).and_return(falho)

    tracker = instance_double(ChatwootExceptionTracker, capture_exception: true)
    allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)

    Contacts::BulkDeleteService.new(account: account, contact_ids: [contact.id, outro.id], user: admin).perform

    expect([Contact.exists?(contact.id), Contact.exists?(outro.id), preso.reload.title]).to eq([true, false, 'Preso'])
    expect(tracker).to have_received(:capture_exception)
    falha = Audited.audit_class.find_by!(auditable: account, action: Crm::ExclusaoDefinitiva::FALHOU)
    expect([falha.user, falha.audited_changes]).to eq([admin, { 'alvo' => 'contato', 'motivo' => 'internal_error',
                                                                'contact_id' => contact.id, 'error_class' => 'ActiveRecord::Deadlocked' }])
  end
end
