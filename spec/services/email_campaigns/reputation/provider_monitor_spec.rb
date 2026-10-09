require 'rails_helper'
require 'aws-sdk-cloudwatch'

RSpec.describe EmailCampaigns::Reputation::ProviderMonitor do
  let(:now) { Time.current.change(usec: 0) }
  let(:config) do
    EmailCampaigns::Reputation::ProviderConfig.new('EMAIL_REPUTATION_PROVIDER_MONITOR' => 'true',
                                                   'EMAIL_REPUTATION_AWS_ACCOUNT_ID' => '123456789012')
  end
  let(:ses) { instance_double(EmailCampaigns::Ses::Client, get_account: { 'SendingEnabled' => true, 'EnforcementStatus' => 'HEALTHY' }) }
  let(:cloudwatch) { instance_double(Aws::CloudWatch::Client) }
  let(:monitor) { described_class.new(config: config, ses: ses, cloudwatch: cloudwatch) }

  before { allow(EmailCampaigns::ProviderRecoveryJob).to receive(:perform_later) }

  def point(value, timestamp = Time.current)
    Aws::CloudWatch::Types::GetMetricStatisticsOutput.new(
      datapoints: [Aws::CloudWatch::Types::Datapoint.new(timestamp: timestamp, average: value)]
    )
  end

  def stub_ratios(bounce:, complaint:)
    allow(cloudwatch).to receive(:get_metric_statistics) do |args|
      value = args[:metric_name] == 'Reputation.BounceRate' ? bounce : complaint
      point(value, args[:end_time])
    end
  end

  it 'blocks at the preventive bounce boundary' do
    stub_ratios(bounce: 0.05, complaint: 0.0)
    state = monitor.call
    expect(state).to have_attributes(status: 'blocked', blocked: true)
    expect(state.telemetry.dig('bounce', 'ratio')).to eq(0.05)
    expect(EmailReputationAudit.where(provider_key: config.provider_key, action: 'provider_blocked').count).to eq(1)
  end

  it 'blocks a restricted sending account without metric availability' do
    allow(ses).to receive(:get_account).and_return('SendingEnabled' => false, 'EnforcementStatus' => 'SHUTDOWN')
    expect(cloudwatch).not_to receive(:get_metric_statistics)
    expect(monitor.call).to have_attributes(status: 'blocked', blocked: true)
  end

  it 'blocks complaints at the preventive boundary' do
    stub_ratios(bounce: 0.0, complaint: 0.001)
    expect(monitor.call).to have_attributes(status: 'blocked', blocked: true)
  end

  it 'blocks provider restriction regardless of ratios' do
    allow(ses).to receive(:get_account).and_return('SendingEnabled' => true, 'EnforcementStatus' => 'PROBATION')
    expect(cloudwatch).not_to receive(:get_metric_statistics)
    expect(monitor.call).to have_attributes(status: 'blocked', blocked: true)
  end

  it 'keeps the global gate latched after the first safe observation' do
    stub_ratios(bounce: 0.05, complaint: 0.0)
    state = monitor.call

    travel 5.minutes do
      stub_ratios(bounce: 0.03, complaint: 0.0005)
      monitor.call
      expect(state.reload).to have_attributes(status: 'healthy', blocked: true)
      expect(state.telemetry['recovery_streak']).to eq(1)
    end
  end

  it 'clears the global latch after the required consecutive safe observations' do
    stub_ratios(bounce: 0.05, complaint: 0.0)
    state = monitor.call
    generation = state.harmful_generation

    travel 5.minutes do
      stub_ratios(bounce: 0.03, complaint: 0.0005)
      monitor.call
    end
    travel 10.minutes do
      stub_ratios(bounce: 0.03, complaint: 0.0005)
      monitor.call
      expect(state.reload).to have_attributes(status: 'healthy', blocked: false, harmful_generation: generation)
      expect(state.telemetry['recovery_streak']).to eq(0)
      expect(EmailCampaigns::Reputation::ProviderGate.protection(config: config)).to be_nil
    end

    expect(EmailReputationAudit.where(provider_key: config.provider_key, action: 'provider_recovered').count).to eq(1)
    expect(EmailCampaigns::ProviderRecoveryJob).to have_received(:perform_later).with(config.provider_key, generation)
  end

  it 'does not recover inside the hysteresis band' do
    stub_ratios(bounce: 0.05, complaint: 0.0)
    state = monitor.call

    travel 5.minutes do
      stub_ratios(bounce: 0.045, complaint: 0.0)
      monitor.call
    end
    travel 10.minutes do
      stub_ratios(bounce: 0.045, complaint: 0.0)
      monitor.call
    end

    expect(state.reload).to have_attributes(status: 'healthy', blocked: true)
    expect(state.telemetry['recovery_streak']).to eq(0)
  end

  it 'resets recovery evidence after an unknown collection result' do
    stub_ratios(bounce: 0.05, complaint: 0.0)
    state = monitor.call

    travel 5.minutes do
      stub_ratios(bounce: 0.03, complaint: 0.0005)
      monitor.call
      expect(state.reload.telemetry['recovery_streak']).to eq(1)
    end
    travel 10.minutes do
      allow(ses).to receive(:get_account).and_raise(Net::ReadTimeout)
      monitor.call
      expect(state.reload).to have_attributes(status: 'unknown', blocked: true, error_code: 'Net::ReadTimeout')
      expect(state.telemetry['recovery_streak']).to eq(0)
    end
  end

  it 'never lets automatic recovery bypass a durable manual block' do
    stub_ratios(bounce: 0.05, complaint: 0.0)
    state = monitor.call
    state.update!(manual_block: true)

    travel 5.minutes do
      stub_ratios(bounce: 0.03, complaint: 0.0005)
      monitor.call
    end
    travel 10.minutes do
      stub_ratios(bounce: 0.03, complaint: 0.0005)
      monitor.call
    end

    expect(state.reload.blocked).to be(true)
    expect(EmailCampaigns::Reputation::ProviderGate.protection(config: config)[:code]).to eq('provider_manual_block')
  end

  it 'preserves a known block on collection errors without adding harmful generations' do
    state = EmailProviderState.create!(provider_key: config.provider_key, status: 'blocked', blocked: true,
                                       harmful_generation: 7, observed_at: now - 60, checked_at: now - 60)
    allow(ses).to receive(:get_account).and_raise(Net::ReadTimeout)

    monitor.call

    expect(state.reload).to have_attributes(status: 'blocked', blocked: true, harmful_generation: 7,
                                            error_code: 'Net::ReadTimeout')
  end

  it 'does no work by default and treats missing metric points as unknown' do
    disabled = EmailCampaigns::Reputation::ProviderConfig.new({})
    expect(described_class.new(config: disabled, ses: ses, cloudwatch: cloudwatch).call).to be_nil
    expect(ses).not_to have_received(:get_account)

    empty = Aws::CloudWatch::Types::GetMetricStatisticsOutput.new(datapoints: [])
    allow(cloudwatch).to receive(:get_metric_statistics).and_return(empty)
    expect(monitor.call.status).to eq('unknown')
  end
end
