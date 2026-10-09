require 'rails_helper'

RSpec.describe EmailCampaigns::Sns::EventProcessor do
  let(:campaign) { create(:email_campaign) }
  let(:recipient) { create(:email_campaign_recipient, email_campaign: campaign, status: :sent, ses_message_id: 'ses-1') }
  let(:event) do
    { 'eventType' => 'Bounce', 'mail' => { 'messageId' => recipient.ses_message_id },
      'bounce' => { 'bounceType' => 'Transient', 'bounceSubType' => 'MailboxFull', 'timestamp' => Time.current.iso8601 } }
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
