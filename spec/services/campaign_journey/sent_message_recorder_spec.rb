require 'rails_helper'

# #1002 (P2, D20, D14): the WhatsApp Oficial campaign message is recorded in the contact's
# conversation after Meta accepted it, is never sent again and writes no CRM mark.
RSpec.describe CampaignJourney::SentMessageRecorder, :aggregate_failures do
  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:user) { account_and_user.last }
  let(:channel) { journey_cloud_channel(account) }
  let(:inbox) { channel.inbox }
  let(:graph_messages) { ->(uri) { uri.host == 'graph.facebook.com' && uri.path.end_with?('/messages') } }
  let!(:audience) do
    saved_audience(account: account, user: user, content: "Nome,Celular\nAna Souza,11987654321\nCaio Reis,31987654321\n")
  end

  around do |example|
    with_modified_env(CAMPAIGN_JOURNEY_ENABLED: 'true') { example.run }
  end

  def audience_campaign
    campaign = create(:campaign, account: account, inbox: inbox, audience: [], title: 'Renovação auto — outubro',
                                 template_params: journey_template_params, message: 'Olá, sua apólice vai vencer.')
    CampaignAudienceLink.create!(account: account, campaign: campaign, campaign_import: audience)
    campaign
  end

  def send_with_all_jobs(campaign)
    perform_enqueued_jobs(only: [SendReplyJob, EventDispatcherJob, CampaignJourney::ReplyMarkJob]) do
      Whatsapp::OneoffCampaignService.new(campaign: campaign).perform
    end
  end

  def contact_named(name)
    account.contacts.find_by!(name: name)
  end

  it 'records the accepted message in the contact conversation with campaign and template' do
    sent = stub_graph_messages
    campaign = audience_campaign

    send_with_all_jobs(campaign)

    recipient = CampaignRecipient.find_by!(campaign: campaign, contact: contact_named('Ana Souza'))
    message = Message.find_by!(inbox: inbox, source_id: recipient.source_id)
    expect(sent.size).to eq(2)
    expect(message).to be_outgoing
    expect(message.status).to eq('sent')
    expect(message.content).to eq(recipient.message_content)
    expect(message.conversation.contact).to eq(contact_named('Ana Souza'))
    expect(message.additional_attributes).to include('campaign_id' => campaign.id, 'campaign_template_name' => 'renovacao')
  end

  it 'never sends the recorded message again: exactly one POST per recipient' do
    stub_graph_messages
    campaign = audience_campaign

    send_with_all_jobs(campaign)

    expect(Message.where(inbox: inbox, message_type: :outgoing).count).to eq(2)
    expect(SendReplyJob).to have_been_performed.exactly(2).times
    expect(WebMock).to have_requested(:post, graph_messages).times(2)
  end

  it 'writes no campaign mark at send time (D14)' do
    stub_graph_messages
    send_with_all_jobs(audience_campaign)

    conversations = Conversation.where(inbox: inbox)
    expect(conversations.count).to eq(2)
    expect(conversations.map { |conversation| conversation.additional_attributes.to_h.keys }.flatten)
      .not_to include('campaign', 'campaign_touches', 'campaign_source_ids')
  end

  it 'reuses the open conversation of the contact in the inbox' do
    stub_graph_messages
    ana = contact_named('Ana Souza')
    contact_inbox = ContactInbox.create!(contact: ana, inbox: inbox, source_id: '5511987654321')
    open_conversation = create(:conversation, account: account, inbox: inbox, contact: ana, contact_inbox: contact_inbox)

    send_with_all_jobs(audience_campaign)

    expect(open_conversation.messages.outgoing.count).to eq(1)
    expect(Conversation.where(inbox: inbox, contact: ana).count).to eq(1)
  end

  it 'lets the status webhook update the recorded message' do
    stub_graph_messages
    campaign = audience_campaign
    send_with_all_jobs(campaign)
    recipient = CampaignRecipient.find_by!(campaign: campaign, contact: contact_named('Ana Souza'))

    Whatsapp::IncomingMessageService.new(
      inbox: inbox,
      params: { 'statuses' => [{ 'id' => recipient.source_id, 'status' => 'delivered', 'timestamp' => Time.current.to_i.to_s }] }
        .with_indifferent_access
    ).perform

    expect(Message.find_by!(inbox: inbox, source_id: recipient.source_id).status).to eq('delivered')
    expect(recipient.reload).to be_delivered
  end

  it 'records nothing for an old label campaign' do
    stub_graph_messages
    label = account.labels.create!(title: 'clientes_antigos')
    contact_named('Ana Souza').add_labels([label.title])
    campaign = create(:campaign, account: account, inbox: inbox, audience: [{ 'type' => 'Label', 'id' => label.id }],
                                 template_params: journey_template_params)

    send_with_all_jobs(campaign)

    expect(CampaignRecipient.find_by!(campaign: campaign)).to be_sent
    expect(Message.where(inbox: inbox).count).to eq(0)
  end

  it 'does not record a message Meta refused' do
    stub_graph_messages(failing: ['+5531987654321'])
    campaign = audience_campaign

    send_with_all_jobs(campaign)

    expect(CampaignRecipient.find_by!(campaign: campaign, contact: contact_named('Caio Reis'))).to be_failed
    expect(Message.where(inbox: inbox).count).to eq(1)
  end
end
