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

  it 'permits fresh SES health with the last official rates published ten hours earlier' do
    travel_to now
    allow(cloudwatch).to receive(:get_metric_data).and_return(
      Aws::CloudWatch::Types::GetMetricDataOutput.new(
        metric_data_results: [Aws::CloudWatch::Types::MetricDataResult.new(id: 'rate', status_code: 'Complete',
                                                                           timestamps: [now - 10.hours], values: [0.0001])]
      )
    )

    state = monitor.call

    expect(state).to have_attributes(status: 'healthy', checked_at: now, observed_at: now - 10.hours)
    expect(EmailCampaigns::Reputation::ProviderGate.protection(config: config, now: now)).to be_nil
  end

  it 'keeps incomplete CloudWatch results unknown even when the returned rates look safe' do
    allow(cloudwatch).to receive(:get_metric_data).and_return(
      Aws::CloudWatch::Types::GetMetricDataOutput.new(
        metric_data_results: [Aws::CloudWatch::Types::MetricDataResult.new(id: 'rate', status_code: 'PartialData',
                                                                           timestamps: [now], values: [0])]
      )
    )

    state = monitor.call

    expect(state.status).to eq('unknown')
    expect(EmailCampaigns::Reputation::ProviderGate.protection(config: config)[:code]).to eq('provider_telemetry_unknown')
  end

  it 'reads the latest CloudWatch ratio instead of summing samples or inventing SES GetAccount fields' do
    allow(cloudwatch).to receive(:get_metric_data) do |args|
      value = args[:metric_data_queries].first[:metric_stat][:metric][:metric_name] == 'Reputation.BounceRate' ? 0.10 : 0.0
      expect(args).to include(scan_by: 'TimestampDescending')
      expect(args[:metric_data_queries].first[:metric_stat]).to include(
        metric: { namespace: 'AWS/SES', metric_name: 'Reputation.BounceRate', dimensions: [] }, period: 300, stat: 'Average'
      )
      Aws::CloudWatch::Types::GetMetricDataOutput.new(
        metric_data_results: [
          Aws::CloudWatch::Types::MetricDataResult.new(
            id: 'rate', status_code: 'Complete',
            timestamps: [now - 300, now], values: [0.01, value]
          )
        ]
      )
    end
    monitor.call
    state = EmailProviderState.find_by!(provider_key: config.provider_key)
    expect(state.status).to eq('blocked')
    expect(state.telemetry.dig('bounce', 'ratio')).to eq(0.10)
  end

  it 'blocks a disabled account without depending on CloudWatch availability' do
    allow(ses).to receive(:get_account).and_return('SendingEnabled' => false, 'EnforcementStatus' => 'SHUTDOWN')
    expect(cloudwatch).not_to receive(:get_metric_data)
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

  it 'does not treat an unknown polling error on an existing block as new harmful evidence' do
    state = EmailProviderState.create!(provider_key: config.provider_key, status: 'blocked', blocked: true,
                                       harmful_generation: 7, observed_at: now - 60, checked_at: now - 60)
    allow(ses).to receive(:get_account).and_raise(Net::ReadTimeout)
    travel 1.second do
      monitor.call
    end
    expect(state.reload).to have_attributes(status: 'blocked', blocked: true, harmful_generation: 7,
                                            error_code: 'Net::ReadTimeout')
  end

  it 'does no work by default and treats missing CloudWatch points as unknown' do
    disabled = EmailCampaigns::Reputation::ProviderConfig.new({})
    expect(described_class.new(config: disabled, ses: ses, cloudwatch: cloudwatch).call).to be_nil
    expect(ses).not_to have_received(:get_account)
    allow(cloudwatch).to receive(:get_metric_data).and_return(Aws::CloudWatch::Types::GetMetricDataOutput.new(
                                                                metric_data_results: [
                                                                  Aws::CloudWatch::Types::MetricDataResult.new(
                                                                    id: 'rate', status_code: 'Complete',
                                                                    timestamps: [], values: []
                                                                  )
                                                                ]
                                                              ))
    monitor.call
    expect(EmailProviderState.find_by!(provider_key: config.provider_key).status).to eq('unknown')
  end

  it 'persists a known critical bounce without depending on the second metric request' do
    allow(cloudwatch).to receive(:get_metric_data) do |args|
      raise 'complaint metric unavailable' unless args[:metric_data_queries].first[:metric_stat][:metric][:metric_name] == 'Reputation.BounceRate'

      Aws::CloudWatch::Types::GetMetricDataOutput.new(
        metric_data_results: [
          Aws::CloudWatch::Types::MetricDataResult.new(
            id: 'rate', status_code: 'Complete',
            timestamps: [now], values: [0.10]
          )
        ]
      )
    end
    monitor.call
    expect(EmailProviderState.find_by!(provider_key: config.provider_key).status).to eq('blocked')
    expect(cloudwatch).to have_received(:get_metric_data).once
  end

  it 'updates the same row through healthy, preventive block, unknown and healthy without releasing the latch' do
    ratio = 0.0
    allow(cloudwatch).to receive(:get_metric_data) do |args|
      Aws::CloudWatch::Types::GetMetricDataOutput.new(
        metric_data_results: [
          Aws::CloudWatch::Types::MetricDataResult.new(
            id: 'rate', status_code: 'Complete',
            timestamps: [args[:end_time]], values: [ratio]
          )
        ]
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
    allow(cloudwatch).to receive(:get_metric_data).and_return(Aws::CloudWatch::Types::GetMetricDataOutput.new(
                                                                metric_data_results: [
                                                                  Aws::CloudWatch::Types::MetricDataResult.new(
                                                                    id: 'rate', status_code: 'Complete',
                                                                    timestamps: [now], values: [0]
                                                                  )
                                                                ]
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
    allow(cloudwatch).to receive(:get_metric_data) do |args|
      ratio = args[:metric_data_queries].first[:metric_stat][:metric][:metric_name] == 'Reputation.ComplaintRate' ? 0.001 : 0.0
      Aws::CloudWatch::Types::GetMetricDataOutput.new(
        metric_data_results: [
          Aws::CloudWatch::Types::MetricDataResult.new(
            id: 'rate', status_code: 'Complete',
            timestamps: [now], values: [ratio]
          )
        ]
      )
    end
    expect(monitor.call).to have_attributes(status: 'blocked', blocked: true)
    travel 1.second do
      allow(ses).to receive(:get_account).and_return('SendingEnabled' => true, 'EnforcementStatus' => 'PROBATION')
      expect(monitor.call.telemetry).to include('enforcement_status' => 'PROBATION')
    end
  end

  context 'with automatic recovery' do
    let!(:state) { EmailProviderState.create!(provider_key: config.provider_key, status: 'blocked', blocked: true) }

    before do
      allow(cloudwatch).to receive(:get_metric_data) do |args|
        Aws::CloudWatch::Types::GetMetricDataOutput.new(
          metric_data_results: [
            Aws::CloudWatch::Types::MetricDataResult.new(
              id: 'rate', status_code: 'Complete',
              timestamps: [args[:end_time]], values: [0]
            )
          ]
        )
      end
    end

    it 'recovers only after two fresh healthy checks spanning five minutes and audits the release' do
      travel_to now
      monitor.call
      expect(state.reload).to be_blocked
      travel 299.seconds do
        monitor.call
        expect(state.reload).to be_blocked
      end
      travel 300.seconds do
        monitor.call
        expect(state.reload).not_to be_blocked
        expect(EmailCampaigns::Reputation::ProviderGate.protection(config: config)).to be_nil
      end
      expect(EmailReputationAudit.where(provider_key: config.provider_key, action: 'provider_recovered').count).to eq(1)
    end

    it 'recovers after two fresh healthy checks even when the last published rate is unchanged' do
      allow(cloudwatch).to receive(:get_metric_data).and_return(
        Aws::CloudWatch::Types::GetMetricDataOutput.new(
          metric_data_results: [
            Aws::CloudWatch::Types::MetricDataResult.new(
              id: 'rate', status_code: 'Complete',
              timestamps: [now - 10.hours], values: [0]
            )
          ]
        )
      )
      travel_to now
      monitor.call
      travel 300.seconds do
        monitor.call
        expect(state.reload).not_to be_blocked
      end
    end

    it 'requires recovery ratios below the pause thresholds with a safety margin' do
      allow(cloudwatch).to receive(:get_metric_data) do |args|
        ratio = args[:metric_data_queries].first[:metric_stat][:metric][:metric_name] == 'Reputation.BounceRate' ? 0.041 : 0
        Aws::CloudWatch::Types::GetMetricDataOutput.new(
          metric_data_results: [
            Aws::CloudWatch::Types::MetricDataResult.new(
              id: 'rate', status_code: 'Complete',
              timestamps: [args[:end_time]], values: [ratio]
            )
          ]
        )
      end
      travel_to now
      monitor.call
      travel 300.seconds do
        monitor.call
        expect(state.reload).to be_blocked
        expect(state.telemetry).not_to have_key('recovery_started_at')
      end
    end

    it 'resets recovery after missing telemetry instead of counting the unsafe interval' do
      travel_to now
      monitor.call
      travel 300.seconds do
        allow(ses).to receive(:get_account).and_raise(Net::ReadTimeout)
        monitor.call
        expect(state.reload.telemetry).not_to have_key('recovery_started_at')
      end
      travel 301.seconds do
        allow(ses).to receive(:get_account).and_return('SendingEnabled' => true, 'EnforcementStatus' => 'HEALTHY')
        monitor.call
        expect(state.reload).to be_blocked
      end
    end

    it 'restarts recovery after the previous observation becomes stale' do
      travel_to now
      monitor.call
      travel 901.seconds do
        monitor.call
        expect(state.reload).to be_blocked
        expect(state.telemetry['recovery_started_at']).to eq((now + 901.seconds).iso8601)
      end
    end

    it 'preserves a manual operator block through healthy samples' do
      state.update!(manual_block: true)
      travel_to now
      monitor.call
      travel 300.seconds do
        monitor.call
        expect(state.reload).to have_attributes(blocked: true, manual_block: true)
        expect(state.telemetry).not_to have_key('recovery_started_at')
      end
    end

    it 'resets recovery when an older overlapping poll returns harmful evidence' do
      travel_to now
      monitor.call
      monitor.send(:persist, status: 'blocked', checked_at: now - 1.second, observed_at: now - 1.second)
      expect(state.reload.telemetry).not_to have_key('recovery_started_at')
      travel 300.seconds do
        monitor.call
        expect(state.reload).to be_blocked
      end
    end
  end
end
