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

  it 'reads the latest CloudWatch ratio instead of summing samples or inventing SES GetAccount fields' do
    allow(cloudwatch).to receive(:get_metric_statistics) do |args|
      value = args[:metric_name] == 'Reputation.BounceRate' ? 0.10 : 0.0
      expect(args).to include(namespace: 'AWS/SES', dimensions: [], statistics: ['Average'])
      Aws::CloudWatch::Types::GetMetricStatisticsOutput.new(datapoints: [Aws::CloudWatch::Types::Datapoint.new(timestamp: now - 300, average: 0.01),
                                                                         Aws::CloudWatch::Types::Datapoint.new(timestamp: now, average: value)])
    end
    monitor.call
    state = EmailProviderState.find_by!(provider_key: config.provider_key)
    expect(state.status).to eq('blocked')
    expect(state.telemetry.dig('bounce', 'ratio')).to eq(0.10)
  end

  it 'blocks a disabled account without depending on CloudWatch availability' do
    allow(ses).to receive(:get_account).and_return('SendingEnabled' => false, 'EnforcementStatus' => 'SHUTDOWN')
    expect(cloudwatch).not_to receive(:get_metric_statistics)
    monitor.call
    expect(EmailProviderState.find_by!(provider_key: config.provider_key).status).to eq('blocked')
  end

  it 'preserves a known block on polling errors and does not expose raw error details' do
    EmailProviderState.create!(provider_key: config.provider_key, status: 'blocked', observed_at: now - 3600)
    allow(ses).to receive(:get_account).and_raise(EmailCampaigns::Ses::Error, 'private provider detail')
    monitor.call
    state = EmailProviderState.find_by!(provider_key: config.provider_key)
    expect(state.status).to eq('blocked')
    expect(state.error_code).to eq('EmailCampaigns::Ses::Error')
    expect(state.observed_at).to eq(now - 3600)
  end

  it 'does no work by default and treats missing CloudWatch points as unknown' do
    disabled = EmailCampaigns::Reputation::ProviderConfig.new({})
    expect(described_class.new(config: disabled, ses: ses, cloudwatch: cloudwatch).call).to be_nil
    expect(ses).not_to have_received(:get_account)
    allow(cloudwatch).to receive(:get_metric_statistics).and_return(Aws::CloudWatch::Types::GetMetricStatisticsOutput.new(datapoints: []))
    monitor.call
    expect(EmailProviderState.find_by!(provider_key: config.provider_key).status).to eq('unknown')
  end

  it 'persists a known critical bounce without depending on the second metric request' do
    allow(cloudwatch).to receive(:get_metric_statistics) do |args|
      raise 'complaint metric unavailable' unless args[:metric_name] == 'Reputation.BounceRate'

      Aws::CloudWatch::Types::GetMetricStatisticsOutput.new(
        datapoints: [Aws::CloudWatch::Types::Datapoint.new(timestamp: now, average: 0.10)]
      )
    end
    monitor.call
    expect(EmailProviderState.find_by!(provider_key: config.provider_key).status).to eq('blocked')
    expect(cloudwatch).to have_received(:get_metric_statistics).once
  end

  it 'updates the same row through healthy, preventive block, unknown and healthy without releasing the latch' do
    ratio = 0.0
    allow(cloudwatch).to receive(:get_metric_statistics) do |args|
      Aws::CloudWatch::Types::GetMetricStatisticsOutput.new(
        datapoints: [Aws::CloudWatch::Types::Datapoint.new(timestamp: args[:end_time], average: ratio)]
      )
    end
    state = monitor.call
    expect(state.status).to eq('healthy')
    ratio = 0.05
    travel 1.second do
      expect(monitor.call.id).to eq(state.id)
      expect(state.reload).to have_attributes(status: 'blocked', blocked: true)
    end
    travel 2.seconds do
      allow(ses).to receive(:get_account).and_raise(Net::ReadTimeout)
      monitor.call
      expect(state.reload).to have_attributes(status: 'blocked', blocked: true)
    end
    travel 3.seconds do
      allow(ses).to receive(:get_account).and_return('SendingEnabled' => true, 'EnforcementStatus' => 'HEALTHY')
      ratio = 0.0
      monitor.call
      expect(state.reload).to have_attributes(status: 'healthy', blocked: true)
      expect(EmailCampaigns::Reputation::ProviderGate.protection(config: config)[:code]).to eq('provider_blocked')
    end
    expect(EmailReputationAudit.where(provider_key: config.provider_key, action: 'provider_blocked').count).to eq(1)
  end

  it 'treats a second healthy poll error as unknown on the existing row' do
    allow(cloudwatch).to receive(:get_metric_statistics).and_return(Aws::CloudWatch::Types::GetMetricStatisticsOutput.new(
                                                                      datapoints: [Aws::CloudWatch::Types::Datapoint.new(timestamp: now, average: 0)]
                                                                    ))
    state = monitor.call
    travel 1.second do
      allow(ses).to receive(:get_account).and_raise(Net::ReadTimeout)
      expect(monitor.call.id).to eq(state.id)
      expect(state.reload.status).to eq('unknown')
      expect(state.error_code).to eq('Net::ReadTimeout')
    end
  end

  it 'blocks complaint at the preventive boundary and PROBATION regardless of ratios' do
    allow(cloudwatch).to receive(:get_metric_statistics) do |args|
      ratio = args[:metric_name] == 'Reputation.ComplaintRate' ? 0.001 : 0.0
      Aws::CloudWatch::Types::GetMetricStatisticsOutput.new(
        datapoints: [Aws::CloudWatch::Types::Datapoint.new(timestamp: now, average: ratio)]
      )
    end
    expect(monitor.call).to have_attributes(status: 'blocked', blocked: true)
    travel 1.second do
      allow(ses).to receive(:get_account).and_return('SendingEnabled' => true, 'EnforcementStatus' => 'PROBATION')
      expect(monitor.call.telemetry).to include('enforcement_status' => 'PROBATION')
    end
  end
end
