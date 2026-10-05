require 'rails_helper'

# #1002 (P2, D20, D14): the WhatsApp Oficial campaign message in the conversation. The send never
# creates a conversation; the message goes into an existing one at send, or into the reply's
# conversation when the person answers. It is never sent again and writes no mark at send time.
RSpec.describe CampaignJourney::SentMessageRecorder, :aggregate_failures do
  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:user) { account_and_user.last }
  let(:channel) { journey_cloud_channel(account) }
  let(:inbox) { channel.inbox }
  let(:graph_messages) { ->(uri) { uri.host == 'graph.facebook.com' && uri.path.end_with?('/messages') } }
  let!(:audience) do
    saved_audience(account: account, user: user,
                   content: "Nome,Celular\nAna Souza,11987654321\nBia Lima,21987654321\nCaio Reis,31987654321\n")
  end
  let(:jobs) { [SendReplyJob, EventDispatcherJob, CampaignJourney::ReplyMarkJob] }

  around do |example|
    with_modified_env(CAMPAIGN_JOURNEY_ENABLED: 'true') { example.run }
  ensure
    Redis::Alfred.scan_each(match: 'MESSAGE_SOURCE_KEY::*') { |key| Redis::Alfred.delete(key) }
  end

  def audience_campaign
    campaign = create(:campaign, account: account, inbox: inbox, audience: [], title: 'Renovação auto — outubro',
                                 template_params: journey_template_params, message: 'Olá, sua apólice vai vencer.')
    CampaignAudienceLink.create!(account: account, campaign: campaign, campaign_import: audience)
    campaign
  end

  def send_campaign(campaign)
    perform_enqueued_jobs(only: jobs) { Whatsapp::OneoffCampaignService.new(campaign: campaign).perform }
  end

  def reply_from(phone, text: 'Quero renovar')
    params = {
      phone_number: channel.phone_number, object: 'whatsapp_business_account',
      entry: [{ changes: [{ value: {
        contacts: [{ profile: { name: 'Ana' }, wa_id: phone }],
        messages: [{ from: phone, id: "wamid.reply-#{phone}", text: { body: text }, timestamp: Time.current.to_i.to_s, type: 'text' }]
      } }] }]
    }.with_indifferent_access
    perform_enqueued_jobs(only: jobs) { Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: inbox, params: params).perform }
  end

  def contact_named(name)
    account.contacts.find_by!(name: name)
  end

  def recipient_of(campaign, name)
    CampaignRecipient.find_by!(campaign: campaign, contact: contact_named(name))
  end

  it 'creates no conversation and fires no conversation_created when recipients have none' do
    stub_graph_messages
    allow(Rails.configuration.dispatcher).to receive(:dispatch).and_call_original

    send_campaign(audience_campaign)

    expect(CampaignRecipient.where(status: :sent).count).to eq(3)
    expect(Conversation.where(account: account).count).to eq(0)
    expect(Message.where(account: account).count).to eq(0)
    expect(Rails.configuration.dispatcher).not_to have_received(:dispatch).with(Events::Types::CONVERSATION_CREATED, anything, anything)
    expect(WebMock).to have_requested(:post, graph_messages).times(3)
  end

  it 'puts the campaign message before the reply in the conversation the reply opened, then marks it' do
    stub_graph_messages
    campaign = audience_campaign
    travel_to(2.hours.ago) { send_campaign(campaign) }

    reply_from('5511987654321')

    recipient = recipient_of(campaign, 'Ana Souza')
    conversation = Conversation.find_by!(inbox: inbox, contact: contact_named('Ana Souza'))
    messages = conversation.messages.order(:created_at)
    expect(messages.map { |message| [message.message_type, message.content] })
      .to eq([['outgoing', recipient.message_content], ['incoming', 'Quero renovar']])
    campaign_message = messages.first
    expect(campaign_message.source_id).to eq(recipient.source_id)
    expect(campaign_message.created_at).to be_within(1.second).of(recipient.sent_at)
    expect(campaign_message.status).to eq('sent')
    expect(campaign_message.additional_attributes).to include('campaign_id' => campaign.id, 'campaign_template_name' => 'renovacao')
    expect(conversation.reload.additional_attributes['campaign_source_ids']).to eq(["campaign:whatsapp:#{campaign.id}"])
    expect(Conversation.where(account: account).count).to eq(1)
    expect(WebMock).to have_requested(:post, graph_messages).times(3)
  end

  it 'records at send in an open conversation and does not duplicate it on reply' do
    stub_graph_messages
    ana = contact_named('Ana Souza')
    contact_inbox = ContactInbox.create!(contact: ana, inbox: inbox, source_id: '5511987654321')
    open_conversation = create(:conversation, account: account, inbox: inbox, contact: ana, contact_inbox: contact_inbox)
    campaign = audience_campaign

    send_campaign(campaign)
    expect(open_conversation.messages.outgoing.count).to eq(1)
    expect(SendReplyJob).to have_been_performed.once

    reply_from('5511987654321')

    expect(open_conversation.messages.outgoing.count).to eq(1)
    expect(open_conversation.messages.incoming.count).to eq(1)
    expect(Message.where(source_id: recipient_of(campaign, 'Ana Souza').source_id).count).to eq(1)
    expect(open_conversation.reload.additional_attributes['campaign_source_ids']).to eq(["campaign:whatsapp:#{campaign.id}"])
    expect(Conversation.where(account: account).count).to eq(1)
    expect(WebMock).to have_requested(:post, graph_messages).times(3)
  end

  it 'writes no campaign mark at send time (D14)' do
    stub_graph_messages
    ana = contact_named('Ana Souza')
    contact_inbox = ContactInbox.create!(contact: ana, inbox: inbox, source_id: '5511987654321')
    conversation = create(:conversation, account: account, inbox: inbox, contact: ana, contact_inbox: contact_inbox)

    send_campaign(audience_campaign)

    expect(conversation.reload.additional_attributes.to_h.keys).not_to include('campaign', 'campaign_touches', 'campaign_source_ids')
  end

  it 'lets the status webhook update a message recorded at send' do
    stub_graph_messages
    ana = contact_named('Ana Souza')
    contact_inbox = ContactInbox.create!(contact: ana, inbox: inbox, source_id: '5511987654321')
    create(:conversation, account: account, inbox: inbox, contact: ana, contact_inbox: contact_inbox)
    campaign = audience_campaign
    send_campaign(campaign)
    recipient = recipient_of(campaign, 'Ana Souza')

    Whatsapp::IncomingMessageService.new(
      inbox: inbox,
      params: { 'statuses' => [{ 'id' => recipient.source_id, 'status' => 'delivered', 'timestamp' => Time.current.to_i.to_s }] }
        .with_indifferent_access
    ).perform

    expect(Message.find_by!(inbox: inbox, source_id: recipient.source_id).status).to eq('delivered')
    expect(recipient.reload).to be_delivered
  end

  it 'records nothing for an old label campaign, at send or at reply' do
    stub_graph_messages
    label = account.labels.create!(title: 'clientes_antigos')
    contact_named('Ana Souza').add_labels([label.title])
    campaign = create(:campaign, account: account, inbox: inbox, audience: [{ 'type' => 'Label', 'id' => label.id }],
                                 template_params: journey_template_params)

    send_campaign(campaign)
    reply_from('5511987654321')

    expect(CampaignRecipient.find_by!(campaign: campaign)).to be_sent
    expect(Message.where(inbox: inbox).outgoing.count).to eq(0)
  end
end
