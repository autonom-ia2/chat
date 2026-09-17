require 'rails_helper'

RSpec.describe EmailCampaigns::Sns::EventProcessor do
  let(:campaign) { create(:email_campaign) }
  let(:recipient) { create(:email_campaign_recipient, email_campaign: campaign, status: :sent, ses_message_id: 'ses-1') }
  let(:event) do
    { 'eventType' => 'Bounce', 'mail' => { 'messageId' => recipient.ses_message_id },
      'bounce' => { 'bounceType' => 'Transient', 'bounceSubType' => 'MailboxFull', 'timestamp' => Time.current.iso8601 } }
  end

  stronger_statuses = %w[unsubscribed complained]
  %w[OnAccountSuppressionList OnTenantSuppressionList].each do |subtype|
    it "records Complaint/#{subtype} as durable prevention, retains raw evidence and deduplicates replay" do
      recipient.update_columns(name: 'N' * 300) # rubocop:disable Rails/SkipsModelValidations
      complaint = { 'eventType' => 'Complaint', 'mail' => event['mail'], 'complaint' => { 'complaintSubType' => subtype } }
      2.times { described_class.new(complaint).process }
      state = EmailSuppressionState.find_by!(account: campaign.account, email: recipient.email)
      expect(state).to have_attributes(active: true, reason: 'provider_suppression', expires_at: nil, occurrences: 1)
      expect(state.email_suppression_events.sole.reason).to eq('provider_suppression')
      expect(EmailSuppression.find_by!(account: campaign.account, email: recipient.email).reason).to eq('provider_suppression')
      expect(recipient.reload).to be_suppressed
      expect(recipient.email_events.complaint.sole.payload).to eq(complaint)
      counts = [campaign.reload.complained_count, EmailCampaigns::Reputation::Metrics.new(campaign.account_id).call[:complaints]]
      expect(counts).to eq([0, 0])
      expect(EmailReputationState.find_by!(account: campaign.account).feedback_version).to eq(1)
    end

    it "blocks the same recipient before a future send after Complaint/#{subtype}" do
      complaint = { 'eventType' => 'Complaint', 'mail' => event['mail'], 'complaint' => { 'complaintSubType' => subtype } }
      described_class.new(complaint).process
      future = create(:email_campaign, account: campaign.account, sender_identity: campaign.sender_identity, status: :sending)
      pending = create(:email_campaign_recipient, email_campaign: future, email: recipient.email,
                                                  preflight_status: 'valid', preflight_valid_until: 1.hour.from_now)
      with_modified_env('EMAIL_CAMPAIGN_HYGIENE_MODE' => 'enforce', 'EMAIL_REPUTATION_PROVIDER_BLOCK' => 'false',
                        'EMAIL_REPUTATION_PROVIDER_MONITOR' => 'false') do
        expect(EmailCampaigns::Reputation::Admission.new(future).claim!(pending)).to be(false)
      end
      expect(pending.reload).to have_attributes(status: 'suppressed', sent_at: nil, ses_message_id: nil)
      expect(WebMock).not_to have_requested(:any, /./)
    end

    stronger_statuses.each do |status|
      it "preserves stronger #{status} status and suppression after Complaint/#{subtype}" do
        reason = status == 'unsubscribed' ? 'unsubscribe' : 'complaint'
        recipient.update!(status: status)
        EmailCampaigns::SuppressionRegistry.new(account: campaign.account, email: recipient.email).block!(
          reason: reason, source: 'ses', event_key: 'earlier-stronger-block'
        )
        complaint = { 'eventType' => 'Complaint', 'mail' => event['mail'], 'complaint' => { 'complaintSubType' => subtype } }
        2.times { described_class.new(complaint).process }
        expect(recipient.reload.status).to eq(status)
        expect(EmailSuppressionState.find_by!(account: campaign.account).reason).to eq(reason)
        expect(EmailSuppression.find_by!(account: campaign.account).reason).to eq(reason)
        expect(recipient.email_events.complaint.sole.payload).to eq(complaint)
      end
    end
  end

  [{}, { 'complaintSubType' => nil }, { 'complaintSubType' => 'FutureUnknown' }, nil].each do |details|
    it "keeps a real complaint with #{details.inspect} and its replays as spam evidence" do
      complaint = { 'eventType' => 'Complaint', 'mail' => event['mail'], 'complaint' => details }
      2.times { described_class.new(complaint).process }
      expect(recipient.reload).to be_complained
      expect(EmailSuppressionState.find_by!(account: campaign.account)).to have_attributes(reason: 'complaint', active: true, occurrences: 1)
      expect(EmailSuppression.find_by!(account: campaign.account).reason).to eq('complaint')
      expect(recipient.email_events.complaint.sole.payload).to eq(complaint)
      expect(campaign.reload.complained_count).to eq(1)
      expect(EmailReputationState.find_by!(account: campaign.account).feedback_version).to eq(1)
    end
  end

  it 'deduplicates metrics and soft failures before counting a replay' do
    3.times { described_class.new(event).process }
    expect(recipient.email_events.where(event_type: :bounce).count).to eq(1)
    expect(campaign.reload.bounced_count).to eq(1)
    suppression = EmailSuppressionState.find_by!(account: campaign.account)
    expect(suppression.occurrences).to eq(1)
    expect(suppression.active).to be false
    expect(EmailSuppression.where(account: campaign.account)).to be_empty
    expect(recipient.email_events.first.payload).to eq(event)
  end

  {
    'Suppressed' => 'permanent', 'OnAccountSuppressionList' => 'unknown',
    'OnTenantSuppressionList' => 'unknown', 'EmailValidationSuppressed' => 'unknown'
  }.each do |subtype, classification|
    it "durably blocks #{subtype} without calling the address invalid and deduplicates replay" do
      event['bounce'].merge!('bounceType' => 'Permanent', 'bounceSubType' => subtype)
      2.times { described_class.new(event).process }
      state = EmailSuppressionState.find_by!(account: campaign.account, email: recipient.email)
      expect([state.active, state.reason, state.expires_at, state.occurrences]).to eq([true, 'provider_suppression', nil, 1])
      expect(EmailSuppression.find_by!(account: campaign.account, email: recipient.email).reason).to eq('provider_suppression')
      expect(EmailSuppression.suppressed?(campaign.account, recipient.email)).to be true
      expect(state.email_suppression_events.sole.metadata).to eq('classification' => classification, 'reason_code' => 'provider_suppression')
      expect(recipient.email_events.sole.payload).to eq(event)
      expect(campaign.reload.bounced_count).to eq(1)
    end
  end

  %w[General NoEmail].each do |subtype|
    it "keeps #{subtype} permanent failure distinct from evidence of a missing mailbox" do
      event['bounce'].merge!('bounceType' => 'Permanent', 'bounceSubType' => subtype)
      described_class.new(event).process
      expect(EmailSuppression.suppressed?(campaign.account, recipient.email)).to be true
      expect(EmailSuppressionEvent.last.metadata['reason_code']).to eq('permanent_failure')
      expect(EmailSuppression.find_by!(account: campaign.account, email: recipient.email).reason).to eq('hard_bounce')
    end
  end

  it 'routes UnsubscribedRecipient to permanent opt-out even with an invalid legacy name and replay' do
    recipient.update_columns(name: 'N' * 300) # rubocop:disable Rails/SkipsModelValidations
    event['bounce'].merge!('bounceType' => 'Permanent', 'bounceSubType' => 'UnsubscribedRecipient')
    2.times { described_class.new(event).process }
    expect(recipient.reload).to be_unsubscribed
    expect(EmailSuppression.find_by!(account: campaign.account, email: recipient.email).reason).to eq('unsubscribe')
    state = EmailSuppressionState.find_by!(account: campaign.account, email: recipient.email)
    expect([state.active, state.reason, state.expires_at, state.occurrences]).to eq([true, 'unsubscribe', nil, 1])
    expect(state.email_suppression_events.sole.metadata).to eq('classification' => 'unknown', 'reason_code' => 'unsubscribe')
    expect(recipient.email_events.where(event_type: :unsubscribe).count).to eq(1)
    expect(recipient.email_events.where(event_type: :bounce).sole.payload).to eq(event)
    expect(campaign.reload.unsubscribed_count).to eq(1)
  end

  it 'promotes provider protection to opt-out and keeps it after a later provider bounce' do
    registry = EmailCampaigns::SuppressionRegistry.new(account: campaign.account, email: recipient.email)
    registry.block!(reason: 'provider_suppression', source: 'ses', event_key: 'earlier-provider-block')
    event['bounce'].merge!('bounceType' => 'Permanent', 'bounceSubType' => 'UnsubscribedRecipient')
    described_class.new(event).process
    registry.record!(reason: 'provider_suppression', source: 'ses', event_key: 'later-provider-block')
    expect(recipient.reload).to be_unsubscribed
    expect(EmailSuppressionState.find_by!(account: campaign.account).reason).to eq('unsubscribe')
    expect(EmailSuppression.find_by!(account: campaign.account).reason).to eq('unsubscribe')
  end

  it 'does not duplicate an existing opt-out when SES reports UnsubscribedRecipient' do
    recipient.update!(status: :unsubscribed)
    recipient.email_events.create!(event_type: :unsubscribe, occurred_at: Time.current)
    event['bounce'].merge!('bounceType' => 'Permanent', 'bounceSubType' => 'UnsubscribedRecipient')
    described_class.new(event).process
    expect(recipient.reload).to be_unsubscribed
    expect(recipient.email_events.where(event_type: :unsubscribe).count).to eq(1)
    expect(EmailSuppression.find_by!(account: campaign.account).reason).to eq('unsubscribe')
  end

  %w[MailboxFull Suppressed OnAccountSuppressionList OnTenantSuppressionList EmailValidationSuppressed].each do |subtype|
    it "preserves unsubscribe status and priority after #{subtype}, complaint and delivery" do
      recipient.update!(status: :unsubscribed)
      EmailCampaigns::SuppressionRegistry.new(account: campaign.account, email: recipient.email).block!(
        reason: 'unsubscribe', source: 'link', event_key: 'unsubscribe:1'
      )
      event['bounce'].merge!('bounceType' => subtype == 'MailboxFull' ? 'Transient' : 'Permanent', 'bounceSubType' => subtype)
      described_class.new(event).process
      described_class.new(event.merge('eventType' => 'Complaint')).process
      described_class.new(event.merge('eventType' => 'Delivery')).process
      expect(recipient.reload).to be_unsubscribed
      expect(EmailSuppression.find_by!(account: campaign.account).reason).to eq('unsubscribe')
    end
  end
end
