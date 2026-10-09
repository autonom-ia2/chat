require 'rails_helper'
require 'aws-sdk-cloudwatch'

RSpec.describe EmailCampaigns::Reputation::ProviderRelease do
  let(:config) do
    EmailCampaigns::Reputation::ProviderConfig.new('EMAIL_REPUTATION_PROVIDER_MONITOR' => 'true',
                                                   'EMAIL_REPUTATION_AWS_ACCOUNT_ID' => '123456789012')
  end
  let(:actor) { create(:user, type: 'SuperAdmin') }
  let(:ses) { instance_double(EmailCampaigns::Ses::Client, get_account: { 'SendingEnabled' => true, 'EnforcementStatus' => 'HEALTHY' }) }
  let(:cloudwatch) { instance_double(Aws::CloudWatch::Client) }
  let(:monitor) { EmailCampaigns::Reputation::ProviderMonitor.new(config: config, ses: ses, cloudwatch: cloudwatch) }
  let(:service) { described_class.new(config: config, monitor: monitor) }
  let!(:state) { EmailProviderState.create!(provider_key: config.provider_key, status: 'blocked', blocked: true) }

  before do
    allow(cloudwatch).to receive(:get_metric_statistics).and_return(Aws::CloudWatch::Types::GetMetricStatisticsOutput.new(
                                                                      datapoints: [Aws::CloudWatch::Types::Datapoint.new(timestamp: Time.current,
                                                                                                                         average: 0)]
                                                                    ))
  end

  it 'requires an actual SuperAdmin and fresh rechecked health, and audits explicit release' do
    expect(service.call(actor: actor, reason: 'Reviewed provider remediation')).to eq(code: 'provider_released')
    expect(state.reload).to have_attributes(status: 'healthy', blocked: false)
    expect(EmailCampaigns::Reputation::ProviderGate.protection(config: config)).to be_nil
    audit = EmailReputationAudit.find_by!(provider_key: config.provider_key, action: 'provider_released')
    expect(audit.actor_id).to eq(actor.id)
    expect(audit.snapshot).not_to have_key('telemetry')
  end

  it 'denies a tenant administrator before querying the provider' do
    admin = create(:user)
    expect { service.call(actor: admin, reason: 'Reviewed provider remediation') }
      .to(raise_error { |error| expect(error.class.name).to eq('Pundit::NotAuthorizedError') })
    expect(ses).not_to have_received(:get_account)
    expect(state.reload.blocked).to be(true)
  end

  it 'cannot override the emergency configuration or disabled monitoring' do
    allow(config).to receive(:manual_block).and_return(true)
    expect { service.call(actor: actor, reason: 'Reviewed provider remediation') }.to raise_error(CustomExceptions::EmailReputationOverride)
    allow(config).to receive_messages(manual_block: false, enabled: false)
    expect { service.call(actor: actor, reason: 'Reviewed provider remediation') }.to raise_error(CustomExceptions::EmailReputationOverride)
    expect(ses).not_to have_received(:get_account)
    expect(state.reload.blocked).to be(true)
  end

  it 'cannot release disabled SES, unknown or stale telemetry' do
    allow(ses).to receive(:get_account).and_return('SendingEnabled' => false, 'EnforcementStatus' => 'SHUTDOWN')
    expect { service.call(actor: actor, reason: 'Reviewed provider remediation') }.to raise_error(CustomExceptions::EmailReputationOverride)
    travel 1.second do
      allow(ses).to receive(:get_account).and_return('SendingEnabled' => true, 'EnforcementStatus' => 'HEALTHY')
      allow(cloudwatch).to receive(:get_metric_statistics).and_return(Aws::CloudWatch::Types::GetMetricStatisticsOutput.new(datapoints: []))
      expect { service.call(actor: actor, reason: 'Reviewed provider remediation') }.to raise_error(CustomExceptions::EmailReputationOverride)
    end
    expect(state.reload.blocked).to be(true)
  end
end
