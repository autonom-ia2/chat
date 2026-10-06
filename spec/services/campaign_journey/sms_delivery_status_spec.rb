require 'rails_helper'

# #1004 review: a delivery callback only changes what the same account sent, and only through the
# provider message id we stored (campaign_recipients.source_id / messages.source_id).
RSpec.describe CampaignJourney::SmsDeliveryStatus, :aggregate_failures do
  let(:account_a) { create(:account) }
  let(:account_b) { create(:account) }
  let(:channel_a) { create(:channel_sms, account: account_a) }
  let(:inbox_a) { channel_a.inbox }

  def recipient_in(inbox, source_id:)
    contact = inbox.account.contacts.create!(name: 'Ana', phone_number: "+55119#{SecureRandom.random_number(10**8).to_s.rjust(8, '0')}")
    campaign = create(:campaign, account: inbox.account, inbox: inbox, title: 'Parcela', message: 'Oi', audience: [])
    CampaignRecipient.create!(account: inbox.account, campaign: campaign, contact: contact, inbox: inbox, status: :sent,
                              source_id: source_id, sent_at: Time.current)
  end

  def bandwidth_event(type, id, owner:, error_code: nil)
    Webhooks::SmsEventsJob.perform_now(
      { type: type, to: '+5511900000000', errorCode: error_code, description: error_code && 'Carrier rejected',
        message: { id: id, owner: owner, direction: 'out' } }.compact.with_indifferent_access
    )
  end

  # Two accounts with the same Bandwidth number (the unique index is dropped inside this example's
  # transaction to build the case; it is rolled back with it).
  def same_number_inbox_in(account)
    ActiveRecord::Base.connection.remove_index(:channel_sms, name: 'index_channel_sms_on_phone_number')
    channel = create(:channel_sms, account: account)
    channel.update_column(:phone_number, channel_a.phone_number) # rubocop:disable Rails/SkipsModelValidations
    channel.inbox
  end

  it 'updates only the account whose inbox holds the provider id when two accounts share the number' do
    inbox_b = same_number_inbox_in(account_b)
    recipient_a = recipient_in(inbox_a, source_id: 'bw-a')
    recipient_b = recipient_in(inbox_b, source_id: 'bw-b')

    bandwidth_event('message-failed', 'bw-a', owner: channel_a.phone_number, error_code: 4720)

    expect(recipient_a.reload).to be_failed
    expect(recipient_b.reload).to be_sent

    bandwidth_event('message-delivered', 'bw-b', owner: channel_a.phone_number)

    expect(recipient_b.reload).to be_delivered
    expect(recipient_a.reload).to be_failed
  end

  it 'updates nobody when both accounts with the number hold the same provider id (ambiguous)' do
    inbox_b = same_number_inbox_in(account_b)
    recipient_a = recipient_in(inbox_a, source_id: 'bw-same')
    conversation_b = create(:conversation, account: account_b, inbox: inbox_b)
    message_b = create(:message, account: account_b, inbox: inbox_b, conversation: conversation_b, message_type: :outgoing,
                                 source_id: 'bw-same', status: :sent)

    bandwidth_event('message-delivered', 'bw-same', owner: channel_a.phone_number)

    expect(recipient_a.reload).to be_sent
    expect(message_b.reload.status).to eq('sent')
  end

  it 'never applies an inbox of another account to a recipient' do
    recipient_a = recipient_in(inbox_a, source_id: 'bw-a')
    inbox_b = create(:channel_sms, account: account_b).inbox

    described_class.apply(inbox: inbox_b, source_id: 'bw-a', status: 'delivered')

    expect(recipient_a.reload).to be_sent
  end

  # Every recipient update needs the provider id we stored: without it nothing changes.
  describe 'provider id required' do
    it 'changes nothing for an event without message id, nor for a recipient that has no source_id' do
      sent = recipient_in(inbox_a, source_id: 'bw-a')
      queued = recipient_in(inbox_a, source_id: nil).tap { |recipient| recipient.update!(status: :queued, sent_at: nil) }

      bandwidth_event('message-delivered', nil, owner: channel_a.phone_number)
      bandwidth_event('message-delivered', '', owner: channel_a.phone_number)
      described_class.apply(inbox: inbox_a, source_id: nil, status: 'failed')
      described_class.apply(inbox: inbox_a, source_id: '', status: 'failed')

      expect([sent.reload.status, queued.reload.status]).to eq(%w[sent queued])
    end

    it 'changes nothing for a Twilio callback without MessageSid or with an id we did not store' do
      twilio = create(:channel_twilio_sms, account: account_a)
      recipient = recipient_in(twilio.inbox, source_id: 'SM1')
      base = { 'AccountSid' => twilio.account_sid, 'MessagingServiceSid' => twilio.messaging_service_sid, 'MessageStatus' => 'failed',
               'ErrorCode' => '30003' }

      Twilio::DeliveryStatusService.new(params: base.with_indifferent_access).perform
      Twilio::DeliveryStatusService.new(params: base.merge('MessageSid' => 'SM-unknown').with_indifferent_access).perform

      expect(recipient.reload).to be_sent
    end
  end
end
