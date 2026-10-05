require 'rails_helper'

# #1004 M3: the SMS appears in the conversation without being sent again, the delivery callbacks
# update the recipient, and a reply counts in "Responderam" with the "Campanha SMS" mark (K1, SMS).
RSpec.describe CampaignJourney::SmsOneoffRecipients, :aggregate_failures do
  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:user) { account_and_user.last }
  # Created before the audience: the sms badge is born on only with an SMS inbox connected.
  let!(:inbox) { journey_twilio_sms_inbox(account) }
  let(:twilio) { inbox.channel }
  let!(:audience) do
    saved_audience(account: account, user: user, content: "Nome,Celular\nAna Souza,11987654321\nCaio Reis,31987654321\n")
  end
  let(:jobs) { [SendReplyJob, EventDispatcherJob, CampaignJourney::ReplyMarkJob] }

  around do |example|
    with_modified_env(CAMPAIGN_JOURNEY_ENABLED: 'true') { example.run }
  end

  def sms_campaign
    campaign = create(:campaign, account: account, inbox: inbox, audience: [], title: 'Parcela outubro', message: 'Oi {{contact.first_name}}!')
    CampaignAudienceLink.create!(account: account, campaign: campaign, campaign_import: audience)
    campaign
  end

  def send_campaign(campaign)
    perform_enqueued_jobs(only: jobs) { Twilio::OneoffSmsCampaignService.new(campaign: campaign).perform }
  end

  def reply_from(phone, text: 'Quero pagar')
    params = { 'AccountSid' => twilio.account_sid, 'MessagingServiceSid' => twilio.messaging_service_sid, 'From' => phone,
               'To' => '+15550001111', 'Body' => text, 'SmsSid' => "SMreply#{phone}" }.with_indifferent_access
    perform_enqueued_jobs(only: jobs) { Twilio::IncomingMessageService.new(params: params).perform }
  end

  def twilio_status(recipient, status, error_code: nil)
    params = { 'AccountSid' => twilio.account_sid, 'MessagingServiceSid' => twilio.messaging_service_sid,
               'MessageSid' => recipient.source_id, 'MessageStatus' => status, 'ErrorCode' => error_code }.compact
    Twilio::DeliveryStatusService.new(params: params.with_indifferent_access).perform
  end

  def contact_named(name)
    account.contacts.find_by!(name: name)
  end

  def recipient_of(campaign, name)
    CampaignRecipient.find_by!(campaign: campaign, contact: contact_named(name))
  end

  it 'records the SMS in an open conversation with the provider id and never sends it again' do
    stub_twilio_sms
    ana = contact_named('Ana Souza')
    contact_inbox = ContactInbox.create!(contact: ana, inbox: inbox, source_id: '+5511987654321')
    open_conversation = create(:conversation, account: account, inbox: inbox, contact: ana, contact_inbox: contact_inbox)
    campaign = sms_campaign

    send_campaign(campaign)

    message = open_conversation.messages.outgoing.sole
    expect([message.content, message.source_id]).to eq(['Oi Ana!', recipient_of(campaign, 'Ana Souza').source_id])
    expect(message.additional_attributes).to eq('campaign_id' => campaign.id)
    expect(SendReplyJob).to have_been_performed.once
    expect(Conversation.where(account: account).count).to eq(1)
    expect(WebMock).to have_requested(:post, CampaignJourneySmsHelpers::TWILIO_MESSAGES).times(2)
  end

  it 'creates no conversation at send, and the reply gets the SMS first, the mark and counts in Responderam' do
    stub_twilio_sms
    campaign = sms_campaign
    travel_to(2.hours.ago) { send_campaign(campaign) }
    expect(Conversation.where(account: account).count).to eq(0)

    reply_from('+5511987654321')

    recipient = recipient_of(campaign, 'Ana Souza')
    conversation = Conversation.find_by!(inbox: inbox, contact: contact_named('Ana Souza'))
    messages = conversation.messages.order(:created_at)
    expect(messages.map { |item| [item.message_type, item.content] }).to eq([['outgoing', 'Oi Ana!'], ['incoming', 'Quero pagar']])
    expect(messages.first.source_id).to eq(recipient.source_id)
    expect(messages.first.created_at).to be_within(1.second).of(recipient.sent_at)
    touch = conversation.reload.additional_attributes['campaign_touches'].sole
    expect(touch).to include('source' => 'campaign_sms', 'source_id' => "campaign:sms:#{campaign.id}", 'headline' => 'Parcela outubro')
    expect(CampaignJourney::CampaignMarks.replied_count(campaign)).to eq(1)
    expect(WebMock).to have_requested(:post, CampaignJourneySmsHelpers::TWILIO_MESSAGES).times(2)
  end

  it 'does not mark a reply that arrives after 72 hours' do
    stub_twilio_sms
    campaign = sms_campaign
    travel_to(73.hours.ago) { send_campaign(campaign) }

    reply_from('+5511987654321')

    conversation = Conversation.find_by!(inbox: inbox, contact: contact_named('Ana Souza'))
    expect(conversation.additional_attributes.to_h).not_to have_key('campaign_touches')
    expect(CampaignJourney::CampaignMarks.replied_count(campaign)).to eq(0)
  end

  describe 'delivery callbacks' do
    it 'Twilio delivered and undelivered update the recipients, with the reason' do
      stub_twilio_sms
      campaign = sms_campaign
      send_campaign(campaign)

      twilio_status(recipient_of(campaign, 'Ana Souza'), 'delivered')
      twilio_status(recipient_of(campaign, 'Caio Reis'), 'undelivered', error_code: '30003')

      expect(recipient_of(campaign, 'Ana Souza')).to be_delivered
      caio = recipient_of(campaign, 'Caio Reis')
      expect([caio.status, caio.error_code, caio.error_message]).to eq(['failed', '30003', 'Unreachable destination handset'])
    end

    it 'never turns a delivered recipient into failed' do
      stub_twilio_sms
      campaign = sms_campaign
      send_campaign(campaign)
      ana = recipient_of(campaign, 'Ana Souza')

      twilio_status(ana, 'delivered')
      twilio_status(ana, 'failed', error_code: '30008')

      expect(ana.reload).to be_delivered
    end

    context 'with Bandwidth' do
      let(:inbox) { journey_bandwidth_inbox(account) }

      def sms_campaign
        campaign = create(:campaign, account: account, inbox: inbox, audience: [], title: 'Parcela outubro', message: 'Oi!')
        CampaignAudienceLink.create!(account: account, campaign: campaign, campaign_import: audience)
        campaign
      end

      def bandwidth_event(type, recipient, **extra)
        Webhooks::SmsEventsJob.perform_now(
          { type: type, to: recipient.contact.phone_number, description: extra[:description], errorCode: extra[:error_code],
            message: { id: recipient.source_id, owner: inbox.channel.phone_number, direction: 'out' } }.compact.with_indifferent_access
        )
      end

      it 'message-delivered and message-failed update the recipients, with the reason' do
        stub_bandwidth_sms
        campaign = sms_campaign
        Sms::OneoffSmsCampaignService.new(campaign: campaign).perform

        bandwidth_event('message-delivered', recipient_of(campaign, 'Ana Souza'))
        bandwidth_event('message-failed', recipient_of(campaign, 'Caio Reis'), error_code: 4720, description: 'Carrier rejected')

        expect(recipient_of(campaign, 'Ana Souza')).to be_delivered
        caio = recipient_of(campaign, 'Caio Reis')
        expect([caio.status, caio.error_code, caio.error_message]).to eq(['failed', '4720', '4720 - Carrier rejected'])
      end

      # Chatwoot's job looked the channel up by `to` (the customer) and built the service with
      # `channel:`; the fork module finds the inbox by the owner, so the conversation message moves.
      it 'updates the status of the SMS in the conversation' do
        stub_bandwidth_sms
        conversations = ['Ana Souza', 'Caio Reis'].to_h do |name|
          contact = contact_named(name)
          contact_inbox = ContactInbox.create!(contact: contact, inbox: inbox, source_id: contact.phone_number)
          [name, create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)]
        end
        campaign = sms_campaign
        Sms::OneoffSmsCampaignService.new(campaign: campaign).perform

        bandwidth_event('message-delivered', recipient_of(campaign, 'Ana Souza'))
        bandwidth_event('message-failed', recipient_of(campaign, 'Caio Reis'), error_code: 4720, description: 'Carrier rejected')

        expect(conversations['Ana Souza'].messages.outgoing.sole.status).to eq('delivered')
        failed = conversations['Caio Reis'].messages.outgoing.sole
        expect([failed.status, failed.external_error]).to eq(['failed', '4720 - Carrier rejected'])
      end
    end
  end
end
