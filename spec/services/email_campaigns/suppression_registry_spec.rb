require 'rails_helper'

RSpec.describe EmailCampaigns::SuppressionRegistry do
  let(:account) { create(:account) }
  let(:registry) { described_class.new(account: account, email: ' Person+tag@Example.org ') }

  it 'normalizes case, isolates accounts and preserves plus tags' do
    registry.block!(reason: 'unsubscribe', source: 'link', event_key: 'unsubscribe:1')
    expect(EmailSuppression.suppressed?(account, 'PERSON+TAG@example.org')).to be true
    expect(EmailSuppression.suppressed?(create(:account), 'person+tag@example.org')).to be false
    expect(EmailSuppression.suppressed?(account, 'person@example.org')).to be false
  end

  it 'deduplicates events and never downgrades an opt-out' do
    registry.block!(reason: 'unsubscribe', source: 'link', event_key: 'unsubscribe:1')
    3.times { |i| registry.record!(reason: 'temporary_failure', source: 'ses', event_key: "bounce:#{i}") }
    registry.block!(reason: 'hard_bounce', source: 'ses', event_key: 'hard:1')
    registry.block!(reason: 'complaint', source: 'ses', event_key: 'spam:1')
    registry.block!(reason: 'provider_suppression', source: 'ses', event_key: 'provider:1')
    2.times { registry.block!(reason: 'unsubscribe', source: 'link', event_key: 'unsubscribe:1') }
    suppression = EmailSuppressionState.find_by!(account: account)
    expect(suppression.reason).to eq('unsubscribe')
    expect(suppression.expires_at).to be_nil
    expect(suppression.occurrences).to eq(7)
    expect(suppression.email_suppression_events.count).to eq(7)
    expect(EmailSuppression.find_by!(account: account).reason).to eq('unsubscribe')
  end

  it 'quarantines only after three distinct failures and expiry does not alter recipient history' do
    3.times { registry.record!(reason: 'temporary_failure', source: 'ses', event_key: 'same') }
    expect(EmailSuppression.suppressed?(account, 'person+tag@example.org')).to be false
    registry.record!(reason: 'temporary_failure', source: 'ses', event_key: 'second')
    registry.record!(reason: 'temporary_failure', source: 'ses', event_key: 'third')
    expect(EmailSuppression.suppressed?(account, 'person+tag@example.org')).to be true
    campaign = create(:email_campaign, account: account, status: :sent)
    historical = create(:email_campaign_recipient, email_campaign: campaign, email: 'person+tag@example.org', status: :suppressed)
    allow(EmailCampaigns::Config).to receive(:enabled?).and_return(true)
    travel 73.hours do
      expect(EmailSuppression.suppressed_set_for(account)).to be_empty
      expect { EmailCampaigns::RecipientPreflightJob.perform_now(campaign.id) }.not_to have_enqueued_job(EmailCampaigns::DeliveryJob)
      expect([historical.reload.status, campaign.reload.status]).to eq(%w[suppressed sent])
      future = create(:email_campaign, account: account, sender_identity: campaign.sender_identity)
      csv = "name,email\nPerson,person+tag@example.org\n"
      imported = EmailCampaigns::RecipientImporter.new(future, csv, filename: 'requested.csv').perform
      expect([imported.imported, future.email_campaign_recipients.first.status]).to eq([1, 'pending'])
    end
    expect(EmailSuppressionState.find_by!(account: account).reason).to eq('temporary_failure')
  end

  it 'does not count old failures towards a new quarantine' do
    registry.record!(reason: 'temporary_failure', source: 'ses', event_key: 'old', occurred_at: 8.days.ago)
    2.times { |i| registry.record!(reason: 'temporary_failure', source: 'ses', event_key: "new:#{i}") }
    expect(EmailSuppression.suppressed_set_for(account)).to be_empty
  end

  it 'retains every legacy positive even with arbitrary release authorization' do
    suppression = EmailSuppression.create!(account: account, email: 'person+tag@example.org', reason: nil, source: 'import')
    3.times { |i| registry.record!(reason: 'temporary_failure', source: 'ses', event_key: "bounce:#{i}") }
    expect { registry.release!(source: 'manual', event_key: 'release:1', authorization: '') }.to raise_error(ArgumentError)
    expect do
      registry.release!(source: 'manual', event_key: 'release:1', authorization: 'approved-change-reference')
    end.to raise_error(ArgumentError)
    expect(EmailSuppression.suppressed_set_for(account)).to include(suppression.email)
    expect(EmailSuppressionEvent.where(action: 'release')).to be_empty
  end

  it 'can release only manual state without any permanent legacy entry' do
    EmailSuppressionState.create!(account: account, email: 'person+tag@example.org', active: true, reason: 'manual', created_at: Time.current)
    registry.release!(source: 'manual', event_key: 'release', authorization: 'reviewed-reference')
    expect(EmailSuppression.suppressed_set_for(account)).to be_empty
    expect(EmailSuppressionEvent.where(action: 'release').sole.metadata).to include('authorization' => 'reviewed-reference')
  end

  it 'rejects a campaign from another account' do
    other = create(:email_campaign)
    expect do
      described_class.new(account: account, email: 'person@example.org', campaign: other)
    end.to raise_error(ArgumentError)
  end

  it 'never expires a strong block created by an older writer' do
    EmailSuppression.create!(account: account, email: 'person+tag@example.org', reason: 'complaint')
    registry.record!(reason: 'temporary_failure', source: 'ses', event_key: 'soft:1')
    expect(EmailSuppression.suppressed?(account, 'person+tag@example.org')).to be true
    expect(EmailSuppression.find_by!(account: account).reason).to eq('complaint')
  end

  it 'prioritizes complaints over permanent failure and does not expire manual suppression' do
    registry.block!(reason: 'hard_bounce', source: 'ses', event_key: 'hard:1')
    registry.block!(reason: 'manual', source: 'manual', event_key: 'manual:1')
    3.times { |i| registry.record!(reason: 'temporary_failure', source: 'ses', event_key: "soft:#{i}") }
    expect(EmailSuppression.find_by!(account: account).reason).to eq('manual')
    registry.block!(reason: 'complaint', source: 'ses', event_key: 'complaint:1')
    registry.block!(reason: 'hard_bounce', source: 'ses', event_key: 'hard:2')
    expect(EmailSuppression.find_by!(account: account).reason).to eq('complaint')
    travel 1.year do
      expect(EmailSuppression.suppressed?(account, 'person+tag@example.org')).to be true
    end
  end

  it 'rolls back state and audit if the permanent mirror cannot be written' do
    allow(EmailSuppression).to receive(:insert_all).and_raise(StandardError, 'synthetic mirror failure')
    expect do
      registry.block!(reason: 'unsubscribe', source: 'link', event_key: 'must-be-atomic')
    end.to raise_error(StandardError, 'synthetic mirror failure')
    expect(EmailSuppressionState.where(account: account)).to be_empty
    expect(EmailSuppressionEvent.where(account: account)).to be_empty
    expect(EmailSuppression.where(account: account)).to be_empty
  end

  %w[unsubscribe complaint hard_bounce manual provider_suppression].each do |reason|
    it "cannot release a permanent #{reason} with an arbitrary authorization string" do
      registry.block!(reason: reason, source: 'manual', event_key: "permanent:#{reason}")
      expect do
        registry.release!(source: 'manual', event_key: 'release', authorization: 'arbitrary-reference')
      end.to raise_error(ArgumentError)
      expect(EmailSuppression.suppressed?(account, 'person+tag@example.org')).to be true
      expect(EmailSuppressionEvent.where(account: account).count).to eq(1)
    end
  end

  it 'retains provider protection for future imports and dispatches, including legacy readers' do
    campaign = create(:email_campaign, account: account, status: :sending)
    pending = create(:email_campaign_recipient, email_campaign: campaign, email: 'person+tag@example.org')
    registry.record!(reason: 'provider_suppression', source: 'ses', event_key: 'provider:1')
    3.times { |i| registry.record!(reason: 'temporary_failure', source: 'ses', event_key: "soft:#{i}") }
    travel 1.year do
      expect(EmailSuppression.where(account_id: account.id).pluck(:email)).to include(pending.email)
      expect(EmailSuppression.blocking_reasons_for(account, [pending.email])).to eq(pending.email => 'provider_suppression')
      expect(EmailSuppression.suppressed_set_for(account)).to include(pending.email)
      expect(EmailSuppression.suppressed?(create(:account), pending.email)).to be false
      future = create(:email_campaign, account: account, sender_identity: campaign.sender_identity)
      result = EmailCampaigns::RecipientImporter.new(future, "name,email\nPerson,#{pending.email}\n", filename: 'synthetic.csv').perform
      expect(result.suppressed).to eq(1)
      expect(EmailCampaigns::DeliveryClaim.new(campaign).claim(pending)).to eq(:suppressed)
    end
  end

  it 'preserves an older opt-out when recording provider protection' do
    EmailSuppression.create!(account: account, email: 'person+tag@example.org', reason: 'unsubscribe', source: 'link')
    registry.record!(reason: 'provider_suppression', source: 'ses', event_key: 'provider:1')
    expect(EmailSuppression.find_by!(account: account).reason).to eq('unsubscribe')
    expect(EmailSuppression.blocking_reasons_for(account, ['person+tag@example.org'])).to eq('person+tag@example.org' => 'unsubscribe')
  end

  it 'rolls back provider protection and its audit if the legacy mirror fails' do
    allow(EmailSuppression).to receive(:insert_all).and_raise(StandardError, 'synthetic mirror failure')
    expect do
      registry.record!(reason: 'provider_suppression', source: 'ses', event_key: 'provider:1')
    end.to raise_error(StandardError, 'synthetic mirror failure')
    expect(EmailSuppressionState.where(account: account)).to be_empty
    expect(EmailSuppressionEvent.where(account: account)).to be_empty
    expect(EmailSuppression.where(account: account)).to be_empty
  end
end
