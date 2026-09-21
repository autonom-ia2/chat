require 'rails_helper'

# Issue #556. A escalada por tempo lia `card.primary_conversation`, que é a PRIMEIRA conversa
# do contato. O convite tinha saído na conversa viva (#553), então a escalada punha o supervisor
# numa conversa antiga que ninguém está lendo — e, pior, a guarda `assignee_id.present?` olhava
# essa conversa antiga: quem já tinha pegado a conversa viva era atropelado 15 minutos depois.
RSpec.describe Crm::Ai::HandoffEscalationJob do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agente_convidado) { create(:user, account: account) }
  let(:supervisor) { create(:user, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:inbox) do
    # Auto-assignment nativo desligado: com a presença stubada como online, o RoundRobin
    # atribuiria a conversa na criação e o job pularia por já-atribuída.
    create_crm_inbox(account: account, members: [agente_convidado, supervisor])
      .tap { |created| created.update!(enable_auto_assignment: false) }
  end
  let(:conversa_antiga) { create_crm_conversation(account: account, inbox: inbox, contact: contact) }
  let(:conversa_viva) { create_crm_conversation(account: account, inbox: inbox, contact: contact) }
  let(:notification_builder) { instance_double(NotificationBuilder, perform: true) }

  around do |example|
    with_modified_env CRM_KANBAN_ENABLED: 'true', CRM_AI_ENABLED: 'true' do
      example.run
    end
  end

  before do
    allow(Rails.configuration.dispatcher).to receive(:dispatch)
    allow(OnlineStatusTracker).to receive(:get_available_users)
      .with(account.id).and_return(supervisor.id.to_s => 'online')
  end

  def config_base
    {
      'enabled' => true,
      'handoff_mode' => 'r3_invite',
      'pickup_threshold_seconds' => 60,
      'renotify_after_seconds' => 60
    }
  end

  def card_com(config:, primaria:, tambem: [], ciclo: {})
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    stage.update!(metadata: { 'ai_handoff' => config })
    card = account.crm_cards.create!(
      pipeline: pipeline, stage: stage, inbox: inbox, contact: contact,
      primary_conversation: primaria, title: 'Lead com convite R3',
      metadata: metadata_de_convite(ciclo)
    )
    ([primaria] + tambem).each_with_index do |conversa, posicao|
      card.card_conversations.create!(account: account, conversation: conversa, is_primary: posicao.zero?)
    end
    card
  end

  def metadata_de_convite(ciclo_extra)
    ciclo = {
      'cycle_id' => 1,
      'invited_at' => 2.hours.ago.iso8601,
      'invited_agent_id' => agente_convidado.id
    }.merge(ciclo_extra)

    { 'ai' => { 'handoffs' => [ciclo], 'handoff' => ciclo } }
  end

  def ciclo_de(card)
    card.reload.metadata.dig('ai', 'handoffs').first
  end

  # Qual é a viva se decide por atividade, não pela ordem em que o spec criou as conversas.
  # Sem carimbar isto, o teste dependia de qual `let` foi tocado primeiro.
  def separar_no_tempo
    conversa_antiga.update!(last_activity_at: 3.hours.ago)
    conversa_viva.update!(last_activity_at: 1.minute.ago)
  end

  it 'escala na conversa em que o cliente está falando, e não na primária do card' do
    # Arrange
    separar_no_tempo
    conversa_antiga.update!(status: :resolved)
    card = card_com(
      config: config_base.merge('escalation_action' => 'escalate', 'escalation_user_id' => supervisor.id),
      primaria: conversa_antiga, tambem: [conversa_viva]
    )

    # Act
    described_class.perform_now

    # Assert
    expect(conversa_viva.reload.assignee_id).to eq(supervisor.id)
    expect(conversa_antiga.reload.assignee_id).to be_nil
    expect(ciclo_de(card)['escalated_to']).to eq(supervisor.id)
  end

  it 'não atropela quem já pegou a conversa viva' do
    # Arrange — o corretor pegou a conversa nova; a primária antiga está sem ninguém, e era ela
    # que a guarda de já-atribuída olhava. Quinze minutos depois o supervisor entrava por cima.
    separar_no_tempo
    conversa_viva.update!(assignee: agente_convidado)
    card = card_com(
      config: config_base.merge('escalation_action' => 'escalate', 'escalation_user_id' => supervisor.id),
      primaria: conversa_antiga, tambem: [conversa_viva]
    )

    # Act
    described_class.perform_now

    # Assert
    expect(conversa_viva.reload.assignee_id).to eq(agente_convidado.id)
    expect(conversa_antiga.reload.assignee_id).to be_nil
    expect(ciclo_de(card)['escalated_at']).to be_blank
  end

  it 're-notifica o agente convidado apontando para a conversa viva' do
    # Arrange
    separar_no_tempo
    conversa_antiga.update!(status: :resolved)
    card = card_com(
      config: config_base.merge('escalation_action' => 'renotify'),
      primaria: conversa_antiga, tambem: [conversa_viva]
    )

    # Assert do destino da notificação: é o link que o agente clica
    expect(NotificationBuilder).to receive(:new).with(
      notification_type: 'conversation_handoff_request',
      user: agente_convidado,
      account: account,
      primary_actor: conversa_viva,
      secondary_actor: nil
    ).and_return(notification_builder)

    # Act
    described_class.perform_now

    # Assert
    expect(ciclo_de(card)['renotify_count']).to eq(1)
    expect(ConversationParticipant.exists?(conversation: conversa_viva, user: agente_convidado)).to be(true)
    expect(ConversationParticipant.exists?(conversation: conversa_antiga, user: agente_convidado)).to be(false)
  end

  it 'com uma conversa só, continua escalando nela' do
    # Arrange — o caminho que já funcionava não pode mudar
    card = card_com(
      config: config_base.merge('escalation_action' => 'escalate', 'escalation_user_id' => supervisor.id),
      primaria: conversa_viva
    )

    # Act
    described_class.perform_now

    # Assert
    expect(conversa_viva.reload.assignee_id).to eq(supervisor.id)
    expect(ciclo_de(card)['escalated_at']).to be_present
  end
end
