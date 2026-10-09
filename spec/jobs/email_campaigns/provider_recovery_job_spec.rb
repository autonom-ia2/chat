require 'rails_helper'

RSpec.describe EmailCampaigns::ProviderRecoveryJob do
  let(:account) { create(:account) }
  let(:identity) { EmailSenderIdentity.create!(account: account, domain: 'example.com', status: :verified) }

  around do |example|
    with_modified_env(
      'EMAIL_REPUTATION_PROVIDER_MONITOR' => 'true',
      'EMAIL_REPUTATION_AWS_ACCOUNT_ID' => '123456789012',
      'EMAIL_CAMPAIGN_HYGIENE_MODE' => 'shadow'
    ) { example.run }
  end

  before do
    allow(EmailCampaigns::Config).to receive(:enabled?).and_return(true)
    allow(EmailCampaigns::DeliveryJob).to receive(:perform_later)
  end

  def paused_campaign(code:, name:)
    campaign = EmailCampaign.create!(
      account: account, sender_identity: identity, name: name, subject: 'Hello',
      body_html: '<p>Hello</p>', status: :paused,
      pause_reason: { kind: 'provider', code: code }
    )
    campaign.email_campaign_recipients.create!(email: "#{name.parameterize}@example.org")
    campaign
  end

  it 'resumes only campaigns parked by recoverable global protection' do
    config = EmailCampaigns::Reputation::ProviderConfig.new
    state = EmailProviderState.create!(
      provider_key: config.provider_key, status: 'healthy', blocked: false,
      observed_at: Time.current, checked_at: Time.current, harmful_generation: 3
    )
    blocked = paused_campaign(code: 'provider_blocked', name: 'global-block')
    unknown = paused_campaign(code: 'provider_telemetry_unknown', name: 'telemetry')
    manual = EmailCampaign.create!(
      account: account, sender_identity: identity, name: 'manual', subject: 'Hello',
      body_html: '<p>Hello</p>', status: :paused,
      pause_reason: { kind: 'manual', code: 'manual_pause' }
    )
    manual.email_campaign_recipients.create!(email: 'manual@example.org')

    described_class.perform_now(config.provider_key, state.harmful_generation)

    expect(blocked.reload).to be_sending
    expect(unknown.reload).to be_sending
    expect(manual.reload).to be_paused
  end

  it 'does nothing while the global gate is still protected' do
    config = EmailCampaigns::Reputation::ProviderConfig.new
    state = EmailProviderState.create!(
      provider_key: config.provider_key, status: 'blocked', blocked: true,
      observed_at: Time.current, checked_at: Time.current, harmful_generation: 4
    )
    campaign = paused_campaign(code: 'provider_blocked', name: 'still-blocked')

    described_class.perform_now(config.provider_key, state.harmful_generation)

    expect(campaign.reload).to be_paused
  end

  it 'ignores a stale recovery job generation' do
    config = EmailCampaigns::Reputation::ProviderConfig.new
    state = EmailProviderState.create!(
      provider_key: config.provider_key, status: 'healthy', blocked: false,
      observed_at: Time.current, checked_at: Time.current, harmful_generation: 5
    )
    campaign = paused_campaign(code: 'provider_blocked', name: 'old-generation')

    described_class.perform_now(config.provider_key, 4)

    expect(campaign.reload).to be_paused
    expect(state.reload.harmful_generation).to eq(5)
  end
end
