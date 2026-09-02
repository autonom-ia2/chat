module CrmHelpers
  def create_crm_agent(account:, name: 'Agent User')
    user = User.create!(
      name: name,
      email: "agent-#{SecureRandom.hex(4)}@example.com",
      password: 'Passw0rd!23',
      confirmed_at: Time.current
    )
    account_user = AccountUser.create!(account: account, user: user, role: :agent)
    [user, account_user]
  end

  def create_crm_inbox(account:, name: 'CRM API Inbox', members: [])
    channel = account.api_channels.create!(webhook_url: 'https://crm.invalid/webhook')
    inbox = account.inboxes.create!(name: name, channel: channel)
    inbox.add_members(members.map(&:id)) if members.any?
    inbox
  end

  def create_crm_pipeline(account:, user:, name: 'Funil Comercial')
    pipeline = account.crm_pipelines.create!(name: name, created_by: user, status: :active)
    stage = account.crm_pipeline_stages.create!(pipeline: pipeline, name: 'Novo Lead', position: 0)
    [pipeline, stage]
  end

  def create_crm_stage(account:, pipeline:, name:, position: 1)
    account.crm_pipeline_stages.create!(pipeline: pipeline, name: name, position: position)
  end

  def create_crm_conversation(account:, inbox:, contact:, assignee: nil, team: nil)
    inbox = account.inboxes.find(inbox.id)
    contact = account.contacts.find(contact.id)
    contact_inbox = ContactInboxBuilder.new(contact: contact, inbox: inbox, source_id: "crm-#{SecureRandom.hex(4)}").perform
    conversation = ConversationBuilder.new(
      params: ActionController::Parameters.new(status: 'open', assignee_id: assignee&.id, team_id: team&.id),
      contact_inbox: contact_inbox
    ).perform
    # O after_create_commit load_attributes_created_by_db_triggers copia o display_id (trigger do banco)
    # para o objeto em memoria e o deixa com mudanca NAO persistida. Rails 7.2 recusa `with_lock` nesse
    # estado (7.1 so avisava), entao qualquer caminho que trave a conversa (AssignmentService, jobs de
    # handoff) explodiria com o objeto cru do builder. Em producao a conversa chega recarregada do banco;
    # o reload devolve ao spec o mesmo estado — mesma tecnica do upstream em Ctwa::CampaignBuilder.
    conversation.reload
  end

  def auth_headers(user)
    { 'api_access_token' => user.access_token.token }
  end

  def create_crm_whatsapp_api_inbox(account:, name: 'CRM WAHA', members: [])
    channel = account.api_channels.create!(webhook_url: 'https://waha.invalid/chatwoot')
    channel.enable_whatsapp_api_campaigns!
    inbox = account.inboxes.create!(name: name, channel: channel)
    inbox.add_members(members.map(&:id)) if members.any?
    inbox
  end

  def create_incoming_message(conversation:, content: 'Oi')
    conversation.messages.create!(
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      message_type: :incoming,
      content: content,
      sender: conversation.contact
    )
  end

  def create_whatsapp_api_template(account:, inbox:, user:, name: 'retorno', body: 'Olá {{contact.first_name}}')
    account.whatsapp_api_message_templates.create!(
      inbox: inbox,
      created_by: user,
      updated_by: user,
      name: name,
      body: body
    )
  end
end

RSpec.configure do |config|
  config.include CrmHelpers
end
