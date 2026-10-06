require 'rails_helper'

# chat#1021: outside the messaging window a Channel::Api follow-up is filled by
# WhatsappApiCampaigns::TemplateRenderer; the contact value it inserts stays literal.
RSpec.describe Crm::FollowUps::MessageSender do
  def expired_api_follow_up(contact_name:, body:)
    account, user = create_account_and_user
    inbox = create_crm_whatsapp_api_inbox(account: account, members: [user])
    # WAHA has no 24h window (always a session message); a provider with the window uses the template.
    inbox.channel.enable_whatsapp_api_campaigns!(provider: 'evolution')
    contact = account.contacts.create!(name: contact_name, phone_number: '+5511987654321')
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: user)
    create_incoming_message(conversation: conversation)
    conversation.messages.incoming.last.update!(created_at: 30.hours.ago)
    template = create_whatsapp_api_template(account: account, inbox: inbox, user: user, body: body)
    pipeline, stage = create_crm_pipeline(account: account, user: user)
    card = account.crm_cards.create!(pipeline: pipeline, stage: stage, inbox: inbox, contact: contact,
                                     primary_conversation: conversation, title: 'Lead')
    account.crm_follow_ups.create!(
      card: card, conversation: conversation, title: 'Retornar', due_at: 10.minutes.ago, timezone: 'UTC',
      automation_mode: :auto_send_message, created_by: user,
      metadata: { message_body: 'Olá, retorno combinado', whatsapp_api_message_template_id: template.id }
    )
  end

  it 'keeps a contact name that looks like Liquid literal in the template message' do
    follow_up = expired_api_follow_up(contact_name: '{{publico.plano}} Ana', body: 'Olá {{contact.name}}')

    result = described_class.new(follow_up: follow_up).perform

    expect(result.status).to eq(:sent)
    expect(result.message.reload.content).to eq('Olá {{publico.plano}} Ana')
    expect(result.message.content_attributes['crm_follow_up_send_mode']).to eq('template')
  end

  # Channel::Whatsapp validates source_id as digits only.
  def native_conversation(inbox:, contact:, assignee:)
    contact_inbox = ContactInboxBuilder.new(contact: contact, inbox: inbox, source_id: contact.phone_number.delete('+')).perform
    ConversationBuilder.new(params: ActionController::Parameters.new(status: 'open', assignee_id: assignee.id),
                            contact_inbox: contact_inbox).perform
  end

  # Native WhatsApp template: the AI composer writes final values into template_processed_params.
  def expired_native_follow_up(contact_name:, processed_params:, message_body: 'Olá')
    account, user = create_account_and_user
    inbox = create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false).inbox
    inbox.add_members([user.id])
    contact = account.contacts.create!(name: contact_name, phone_number: '+5511987654321')
    conversation = native_conversation(inbox: inbox, contact: contact, assignee: user)
    create_incoming_message(conversation: conversation)
    conversation.messages.incoming.last.update!(created_at: 30.hours.ago)
    pipeline, stage = create_crm_pipeline(account: account, user: user)
    card = account.crm_cards.create!(pipeline: pipeline, stage: stage, inbox: inbox, contact: contact,
                                     primary_conversation: conversation, title: 'Lead')
    account.crm_follow_ups.create!(
      card: card, conversation: conversation, title: 'Retornar', due_at: 10.minutes.ago, timezone: 'UTC',
      automation_mode: :auto_send_message, created_by: user,
      metadata: { message_body: message_body, template_name: 'continuidade_atendimento', template_language: 'pt_BR',
                  template_processed_params: processed_params }
    )
  end

  it 'keeps the AI-composed values of a native template literal' do
    follow_up = expired_native_follow_up(contact_name: 'Ana',
                                         processed_params: { '1' => '{{publico.plano}} Ana', '2' => '{% if true %}x{% endif %}' })

    result = described_class.new(follow_up: follow_up).perform

    expect(result.status).to eq(:sent)
    processed = result.message.reload.additional_attributes.dig('template_params', 'processed_params')
    expect(processed).to eq('1' => '{{publico.plano}} Ana', '2' => '{% if true %}x{% endif %}')
  end

  it 'still renders Liquid in the message_body of a native template follow-up' do
    follow_up = expired_native_follow_up(contact_name: 'Ana Maria', processed_params: { '1' => 'Ana' },
                                         message_body: 'Olá {{contact.name}}')

    result = described_class.new(follow_up: follow_up).perform

    expect(result.status).to eq(:sent)
    expect(result.message.reload.content).to eq('Olá Ana Maria')
  end

  it 'still fills the variable written in the template' do
    follow_up = expired_api_follow_up(contact_name: 'Ana Maria', body: 'Olá {{contact.first_name}}')

    result = described_class.new(follow_up: follow_up).perform

    expect(result.status).to eq(:sent)
    expect(result.message.reload.content).to eq('Olá Ana')
  end
end
