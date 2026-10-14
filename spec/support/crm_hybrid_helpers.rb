# Cenário do follow-up do CRM numa caixa WhatsApp Oficial (Cloud) com WhatsApp Híbrido (chat#1349):
# conversa com a janela de 24h fechada, card no funil e (opcionalmente) a conexão WAHA pronta.
# Quem usa liga o piloto da conta com `with_modified_env WHATSAPP_HYBRID_ACCOUNT_IDS: '*'`.
module CrmHybridHelpers
  APPROVED_TEMPLATE = {
    'name' => 'retomada_orcamento', 'status' => 'APPROVED', 'language' => 'pt_BR', 'category' => 'UTILITY',
    'components' => [{ 'type' => 'BODY', 'text' => 'Oi {{1}}, conseguiu ver o orçamento?' }]
  }.freeze

  def build_crm_hybrid_scenario(templates: [], hybrid: true, last_inbound_ago: 30.hours.ago)
    account, user = create_account_and_user
    channel = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false,
                                        validate_provider_config: false, message_templates: templates)
    inbox = channel.inbox
    inbox.add_members([user.id])
    contact = account.contacts.create!(name: 'Lead', phone_number: '+5511937016094')
    conversation = crm_hybrid_conversation(inbox: inbox, contact: contact, assignee: user)
    create_incoming_message(conversation: conversation)
    conversation.messages.incoming.last.update!(created_at: last_inbound_ago)
    connection = hybrid ? create_crm_hybrid_connection(account: account, inbox: inbox, channel: channel) : nil
    { account: account, user: user, inbox: inbox, contact: contact, conversation: conversation,
      card: create_crm_hybrid_card(account: account, user: user, inbox: inbox, contact: contact, conversation: conversation),
      connection: connection }
  end

  def create_crm_hybrid_connection(account:, inbox:, channel:)
    WhatsappHybrid::Connection.create!(
      account: account, inbox: inbox, session_name: "hybrid-#{SecureRandom.hex(3)}", status: 'connected',
      connected_phone: channel.phone_number.delete('^0-9'), risk_accepted_at: Time.current, status_checked_at: Time.current
    )
  end

  # Channel::Whatsapp exige source_id numérico, então o helper genérico (crm-<hex>) não serve aqui.
  def crm_hybrid_conversation(inbox:, contact:, assignee:)
    contact_inbox = ContactInboxBuilder.new(contact: contact, inbox: inbox, source_id: contact.phone_number.delete('+')).perform
    ConversationBuilder.new(
      params: ActionController::Parameters.new(status: 'open', assignee_id: assignee.id), contact_inbox: contact_inbox
    ).perform.reload
  end

  def create_crm_hybrid_card(account:, user:, inbox:, contact:, conversation:)
    pipeline, stage = create_crm_pipeline(account: account, user: user)
    pipeline.update!(metadata: { ai: { auto_followup: { enabled: true } } })
    account.crm_cards.create!(pipeline: pipeline, stage: stage, inbox: inbox, contact: contact,
                              primary_conversation: conversation, title: 'Lead')
  end

  TRANSCRIPT_LINE = 'Preciso do orçamento do seguro até sexta, pode me mandar por aqui?'.freeze
  NO_TEMPLATE = { 'index' => -1, 'kind' => 'native', 'name' => '', 'id' => nil, 'language' => nil }.freeze

  # Resposta da IA no formato do schema do compositor (o texto da citação existe na conversa do cenário).
  def crm_hybrid_ai_answer(overrides = {})
    { 'should_send' => true, 'closure_detected' => false, 'open_loop' => 'Orçamento pedido pelo cliente',
      'open_loop_source' => TRANSCRIPT_LINE, 'message_body' => 'Oi! Passando para saber se ainda posso te ajudar com o orçamento.',
      'chosen_template' => NO_TEMPLATE, 'template_variables' => [], 'next_action_owner' => 'cliente',
      'message_kind' => 'cobranca', 'tone' => 'friendly', 'confidence' => 0.9, 'decline_reason' => 'none' }.merge(overrides)
  end

  def crm_hybrid_template_pick(index = 0)
    { 'index' => index, 'kind' => 'native', 'name' => APPROVED_TEMPLATE['name'], 'id' => nil, 'language' => 'pt_BR' }
  end

  # A IA no nível do client: cada chamada devolve a próxima resposta e fica registrada em `ai_calls`
  # (instruções e entrada reais do compositor). Chamar a IA além do esperado reprova o teste.
  # O bloco, se vier, roda no início de cada chamada com o número dela (simula o mundo mudando durante a IA).
  def stub_crm_hybrid_ai(*answers, &during_call)
    @ai_calls = []
    queue = answers.dup
    client = instance_double(Crm::Ai::ResponsesClient)
    allow(client).to receive(:create) do |**request|
      @ai_calls << request
      during_call&.call(@ai_calls.size)
      raise "IA chamada #{@ai_calls.size} vezes; esperado #{answers.size}" if queue.empty?

      { text: queue.shift.to_json, usage: {}, response_id: "resp_#{@ai_calls.size}" }
    end
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(client)
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(
      instance_double(Crm::Ai::CredentialResolver, resolve: { api_key: 'sk-test', api_base: 'https://api.openai.com', source: :system })
    )
    client
  end

  attr_reader :ai_calls

  def ai_call_modes
    ai_calls.map { |call| JSON.parse(call[:input])['mode'] }
  end

  def seed_crm_hybrid_transcript(scenario)
    scenario[:conversation].messages.incoming.last.update!(content: TRANSCRIPT_LINE)
  end

  def create_crm_hybrid_follow_up(scenario, source: 'ai_followup', metadata: {})
    scenario[:account].crm_follow_ups.create!(
      card: scenario[:card], conversation: scenario[:conversation], contact: scenario[:contact], title: 'Retomar',
      due_at: 10.minutes.ago, timezone: 'UTC', automation_mode: :auto_send_message, created_by: scenario[:user],
      metadata: { 'source' => source, 'touch' => 1, 'message_body' => 'rascunho' }.merge(metadata)
    )
  end
end
