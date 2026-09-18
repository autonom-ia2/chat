require 'rails_helper'

RSpec.describe EmailCampaigns::PreflightDecision do # -- focused dynamic suppression regressions
  let(:campaign) { create(:email_campaign, status: :sending) }
  let(:account) { campaign.account }
  let(:recipient) { create(:email_campaign_recipient, email_campaign: campaign, preflight_status: 'review') }
  let(:decision) { described_class.new(config: EmailCampaigns::HygieneConfig.new('EMAIL_CAMPAIGN_HYGIENE_MODE' => 'enforce')) }
  let(:registry) { EmailCampaigns::SuppressionRegistry.new(account: account, email: recipient.email) }

  it 'lets fresh recipients proceed after a new opt-out but keeps the blocked recipient unclaimable' do
    fresh = create(:email_campaign_recipient, email_campaign: campaign, preflight_status: 'valid', preflight_valid_until: 1.hour.from_now)
    recipient
    expect(decision.campaign_allowed?(campaign)).to be false
    registry.block!(reason: 'unsubscribe', source: 'link', event_key: 'later-optout')
    protection = EmailSuppressionState.find_by!(account: account, email: recipient.email).attributes
    expect(decision.campaign_allowed?(campaign)).to be true
    with_modified_env('EMAIL_CAMPAIGN_HYGIENE_MODE' => 'enforce') do
      gate = EmailCampaigns::DeliveryClaim.new(campaign)
      expect(gate.claim(recipient)).to eq(:suppressed)
      expect(gate.dispatch_allowed?(recipient)).to be false
      expect(gate.claim(fresh)).to eq(:claimed)
    end
    expect(EmailSuppressionState.find_by!(account: account, email: recipient.email).attributes).to eq(protection)
  end

  it 'uses only current quarantine and keeps a legacy positive authoritative after expiry' do
    3.times { |i| registry.record!(reason: 'temporary_failure', source: 'ses', event_key: "soft:#{i}") }
    expect(decision.campaign_allowed?(campaign)).to be true
    travel 74.hours do
      expect(decision.campaign_allowed?(campaign)).to be false
      EmailSuppression.create!(account: account, email: recipient.email, reason: 'unsubscribe')
      expect(decision.campaign_allowed?(campaign)).to be true
    end
  end

  it 'does not exclude inactive observations or same-address blocks in another account' do
    registry.record!(reason: 'unknown_bounce', source: 'ses', event_key: 'observation')
    other = create(:account)
    EmailCampaigns::SuppressionRegistry.new(account: other, email: recipient.email)
                                       .block!(reason: 'unsubscribe', source: 'link', event_key: 'other-optout')
    expect(decision.campaign_allowed?(campaign)).to be false
  end

  it 'reads active new-only strong state without releasing it because its timestamp expired' do
    state = EmailSuppressionState.create!(account: account, email: recipient.email, active: true, reason: 'manual', expires_at: 1.day.ago)
    expect(decision.campaign_allowed?(campaign)).to be true
    expect(state.reload).to be_active
    expect(EmailSuppression.where(account: account)).to be_empty
  end

  %w[unchecked invalid review unknown].each do |status|
    it "retains the enforce hold for eligible #{status} recipients" do
      recipient.update!(preflight_status: status, preflight_reason_code: status == 'unknown' ? 'dns_disabled' : status)
      expect(decision.campaign_allowed?(campaign)).to be false
    end
  end

  %w[shadow warning enforce].each do |mode|
    it "refuses an active import in #{mode} even without unresolved recipients" do
      campaign.email_campaign_imports.create!
      config = EmailCampaigns::HygieneConfig.new('EMAIL_CAMPAIGN_HYGIENE_MODE' => mode)
      expect(described_class.new(config: config).campaign_allowed?(campaign)).to be false
    end
  end

  it 'uses bounded authoritative lookups across multiple unresolved batches' do
    rows = (1..501).map do |i|
      { email_campaign_id: campaign.id, email: "blocked#{i}@example.org", status: 0, preflight_status: 'review' }
    end
    EmailCampaignRecipient.insert_all!(rows) # rubocop:disable Rails/SkipsModelValidations
    suppressions = rows.map { |row| { account_id: account.id, email: row[:email], reason: 'manual', created_at: Time.current } }
    EmailSuppression.insert_all!(suppressions) # rubocop:disable Rails/SkipsModelValidations
    sizes = []
    allow(EmailSuppression).to receive(:blocking_reasons_for).and_wrap_original do |original, tenant, emails|
      sizes << emails.size
      original.call(tenant, emails)
    end
    expect(decision.campaign_allowed?(campaign)).to be true
    expect(sizes).to eq([500, 1])
  end
end
