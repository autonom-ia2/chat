require 'rails_helper'
require 'aws-sdk-cloudwatch'

RSpec.describe EmailCampaigns::Reputation::ProviderMonitor do # rubocop:disable RSpec/SpecFilePathFormat -- real overlapping polls
  self.use_transactional_tests = false

  let(:config) do
    EmailCampaigns::Reputation::ProviderConfig.new('EMAIL_REPUTATION_PROVIDER_MONITOR' => 'true',
                                                   'EMAIL_REPUTATION_AWS_ACCOUNT_ID' => SecureRandom.random_number(10**12).to_s.rjust(12, '0'))
  end
  let(:cloudwatch) { instance_double(Aws::CloudWatch::Client) }

  after { EmailProviderState.where(provider_key: config.provider_key).delete_all }

  it 'keeps the newer blocked observation when an older healthy poll finishes late on a separate session' do
    captured = Queue.new
    release = Queue.new
    old_ses = instance_double(EmailCampaigns::Ses::Client)
    allow(old_ses).to receive(:get_account) do
      captured << ActiveRecord::Base.connection.select_value('SELECT pg_backend_pid()')
      release.pop
      { 'SendingEnabled' => true, 'EnforcementStatus' => 'HEALTHY' }
    end
    allow(cloudwatch).to receive(:get_metric_statistics) do |args|
      Aws::CloudWatch::Types::GetMetricStatisticsOutput.new(
        datapoints: [Aws::CloudWatch::Types::Datapoint.new(timestamp: args[:end_time], average: 0)]
      )
    end
    old = described_class.new(config: config, ses: old_ses, cloudwatch: cloudwatch)
    worker = Thread.new { ActiveRecord::Base.connection_pool.with_connection { old.call } }
    begin
      pid = Timeout.timeout(5) { captured.pop }
      expect(ActiveRecord::Base.connection.select_value('SELECT pg_backend_pid()')).not_to eq(pid)
      ses = instance_double(EmailCampaigns::Ses::Client, get_account: { 'SendingEnabled' => false, 'EnforcementStatus' => 'SHUTDOWN' })
      latest = described_class.new(config: config, ses: ses, cloudwatch: cloudwatch).call
    ensure
      release << true
      worker.join(5) || worker.kill.join
    end
    expect(worker.value.id).to eq(latest.id)
    expect(latest.reload).to have_attributes(status: 'blocked', blocked: true)
    expect(EmailProviderState.where(provider_key: config.provider_key).count).to eq(1)
  end

  it 'creates only one valid state when two initial polls race at the unique constraint' do
    reached = Queue.new
    proceed = Queue.new
    allow(EmailProviderState).to receive(:find_by).and_wrap_original do |original, *arguments|
      found = original.call(*arguments)
      unless found
        reached << ActiveRecord::Base.connection.select_value('SELECT pg_backend_pid()')
        proceed.pop
      end
      found
    end
    allow(cloudwatch).to receive(:get_metric_statistics) do |args|
      Aws::CloudWatch::Types::GetMetricStatisticsOutput.new(
        datapoints: [Aws::CloudWatch::Types::Datapoint.new(timestamp: args[:end_time], average: 0)]
      )
    end
    ses = instance_double(EmailCampaigns::Ses::Client, get_account: { 'SendingEnabled' => true, 'EnforcementStatus' => 'HEALTHY' })
    workers = Array.new(2) do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection { described_class.new(config: config, ses: ses, cloudwatch: cloudwatch).call }
      end
    end
    begin
      pids = Timeout.timeout(5) { [reached.pop, reached.pop] }
      expect(pids.uniq.size).to eq(2)
    ensure
      2.times { proceed << true }
      workers.each { |worker| worker.join(5) || worker.kill.join }
    end
    expect(workers.map(&:value).map(&:id).uniq.size).to eq(1)
    expect(EmailProviderState.find_by!(provider_key: config.provider_key)).to have_attributes(status: 'healthy', blocked: false)
  end
end
