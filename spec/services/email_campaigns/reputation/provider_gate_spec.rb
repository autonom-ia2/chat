require 'rails_helper'

RSpec.describe EmailCampaigns::Reputation::ProviderGate do
  let(:now) { Time.current.change(usec: 0) }
  let(:config) do
    EmailCampaigns::Reputation::ProviderConfig.new('EMAIL_REPUTATION_PROVIDER_MONITOR' => 'true',
                                                   'EMAIL_REPUTATION_AWS_ACCOUNT_ID' => '123456789012')
  end

  it 'blocks missing, unknown, stale and future telemetry, with an explicit configurable unknown policy' do
    expect(described_class.protection(config: config, now: now)[:code]).to eq('provider_telemetry_unknown')
    state = EmailProviderState.create!(provider_key: config.provider_key, status: 'healthy', observed_at: now - 901)
    expect(described_class.protection(config: config, now: now)).to be_present
    state.update!(observed_at: now + 1)
    expect(described_class.protection(config: config, now: now)).to be_present
    state.update!(observed_at: now, status: 'unknown')
    expect(described_class.protection(config: config, now: now)).to be_present
    allow(config).to receive(:unknown_action).and_return('allow')
    expect(described_class.protection(config: config, now: now)).to be_nil
    expect(state.reload.status).to eq('unknown')
  end

  it 'keeps manual and durable provider blocks enforced even with monitoring disabled or stale telemetry allowed' do
    state = EmailProviderState.create!(provider_key: config.provider_key, status: 'blocked')
    allow(config).to receive_messages(enabled: false, unknown_action: 'allow')
    expect(described_class.protection(config: config)[:overridable]).to be(false)
    state.update!(status: 'healthy', manual_block: true)
    expect(described_class.protection(config: config)[:code]).to eq('provider_manual_block')
  end

  it 'scopes provider state by AWS account and region, never tenant' do
    EmailProviderState.create!(provider_key: "#{config.provider_key}-other-region", status: 'blocked')
    EmailProviderState.create!(provider_key: config.provider_key, status: 'healthy', observed_at: now)
    expect(described_class.protection(config: config, now: now)).to be_nil
  end
end
