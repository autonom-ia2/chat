require 'rails_helper'

# #2048: toda mensagem do follow-up leva a origem (`crm_follow_up_origem`) ao lado da marca `crm_follow_up_id`, nos três
# caminhos de envio. O painel lê a origem para dizer "Retorno automático" ('retorno': combinado pela IA ou marcado por uma
# pessoa) ou "Follow-up automático" ('follow_up': cadência da IA, lembrete de serviço, automação de etapa).
RSpec.describe Crm::FollowUps::MessageSender do
  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:user) { account_and_user.last }
  let(:contact) { account.contacts.create!(name: 'Lead', phone_number: '+5511987654321') }

  def follow_up_for(conversation, inbox, follow_up_type:, metadata:)
    pipeline, stage = create_crm_pipeline(account: account, user: user)
    card = account.crm_cards.create!(pipeline: pipeline, stage: stage, inbox: inbox, contact: contact,
                                     primary_conversation: conversation, title: 'Lead')
    account.crm_follow_ups.create!(
      card: card, conversation: conversation, title: 'Retornar', due_at: 10.minutes.ago, timezone: 'UTC',
      automation_mode: :auto_send_message, created_by: user, follow_up_type: follow_up_type, metadata: metadata
    )
  end

  def window_expired!(conversation)
    create_incoming_message(conversation: conversation)
    conversation.messages.incoming.last.update!(created_at: 30.hours.ago)
  end

  def marks_of(result)
    expect(result.error).to be_nil
    expect(result.status).to eq(:sent)
    result.message.reload.content_attributes.slice('crm_follow_up_id', 'crm_follow_up_origem')
  end

  it 'retorno marcado por uma pessoa no card vira retorno, mesmo sendo tarefa' do
    inbox = create_crm_whatsapp_api_inbox(account: account, members: [user])
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: user)
    create_incoming_message(conversation: conversation)
    follow_up = follow_up_for(conversation, inbox, follow_up_type: :task, metadata: { message_body: 'Oi, como combinamos' })

    result = described_class.new(follow_up: follow_up).perform

    expect(marks_of(result)).to eq('crm_follow_up_id' => follow_up.id, 'crm_follow_up_origem' => 'retorno')
  end

  it 'retorno combinado pela IA vira retorno (texto de sessão)' do
    inbox = create_crm_whatsapp_api_inbox(account: account, members: [user])
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: user)
    create_incoming_message(conversation: conversation)
    follow_up = follow_up_for(conversation, inbox, follow_up_type: :call,
                                                   metadata: { message_body: 'Olá, retorno combinado', source: 'ai_callback' })

    result = described_class.new(follow_up: follow_up).perform

    expect(marks_of(result)).to eq('crm_follow_up_id' => follow_up.id, 'crm_follow_up_origem' => 'retorno')
  end

  it 'cadência da IA vira follow-up (modelo pela API)' do
    inbox = create_crm_whatsapp_api_inbox(account: account, members: [user])
    # Provedor que não é WAHA, para valer a janela de 24 h da Meta (WAHA sempre manda sessão).
    inbox.channel.enable_whatsapp_api_campaigns!(provider: 'cloud')
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: user)
    window_expired!(conversation)
    template = create_whatsapp_api_template(account: account, inbox: inbox, user: user, body: 'Olá {{contact.first_name}}')
    follow_up = follow_up_for(conversation, inbox, follow_up_type: :message,
                                                   metadata: { message_body: 'Olá', whatsapp_api_message_template_id: template.id,
                                                               source: 'ai_followup' })

    result = described_class.new(follow_up: follow_up).perform

    expect(marks_of(result)).to eq('crm_follow_up_id' => follow_up.id, 'crm_follow_up_origem' => 'follow_up')
    expect(result.message.content_attributes['crm_follow_up_send_mode']).to eq('template')
  end

  it 'automação de etapa vira follow-up (modelo nativo)' do
    channel = create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false)
    inbox = channel.inbox
    inbox.add_members([user.id])
    contact_inbox = ContactInboxBuilder.new(contact: contact, inbox: inbox, source_id: contact.phone_number.delete('+')).perform
    conversation = ConversationBuilder.new(
      params: ActionController::Parameters.new(status: 'open', assignee_id: user.id), contact_inbox: contact_inbox
    ).perform
    window_expired!(conversation)
    follow_up = follow_up_for(conversation, inbox, follow_up_type: :call,
                                                   metadata: { message_body: 'Olá', template_name: 'continuidade_atendimento',
                                                               template_language: 'pt_BR', source: 'stage_automation' })

    result = described_class.new(follow_up: follow_up).perform

    expect(marks_of(result)).to eq('crm_follow_up_id' => follow_up.id, 'crm_follow_up_origem' => 'follow_up')
    expect(result.message.content_attributes['crm_follow_up_send_mode']).to eq('template')
  end
end
