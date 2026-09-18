require 'rails_helper'
require 'aws-sdk-cloudwatch'

RSpec.describe EmailCampaigns::Reputation::ProviderMonitor do # rubocop:disable RSpec/SpecFilePathFormat -- real overlapping polls
  self.use_transactional_tests = false

  let(:config) do
    EmailCampaigns::Reputation::ProviderConfig.new('EMAIL_REPUTATION_PROVIDER_MONITOR' => 'true',
                                                   'EMAIL_REPUTATION_AWS_ACCOUNT_ID' => SecureRandom.random_number(10**12).to_s.rjust(12, '0'))
  end
  let(:cloudwatch) { instance_double(Aws::CloudWatch::Client) }

  def stub_safe_cloudwatch(client)
    allow(client).to receive(:get_metric_statistics) do |args|
      Aws::CloudWatch::Types::GetMetricStatisticsOutput.new(
        datapoints: [Aws::CloudWatch::Types::Datapoint.new(timestamp: args[:end_time], average: 0)]
      )
    end
  end

  def pause_monitor_after_collection(real_monitor, collected, proceed)
    monitor = instance_double(described_class)
    allow(monitor).to receive(:call) do
      observed = real_monitor.call
      collected << observed.id
      proceed.pop
      observed
    end
    monitor
  end

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

  it 'latches and audits an older harmful poll that finishes after newer healthy telemetry' do
    captured = Queue.new
    release = Queue.new
    harmful_ses = instance_double(EmailCampaigns::Ses::Client)
    allow(harmful_ses).to receive(:get_account) do
      captured << ActiveRecord::Base.connection.select_value('SELECT pg_backend_pid()')
      release.pop
      { 'SendingEnabled' => true, 'EnforcementStatus' => 'PROBATION' }
    end
    allow(cloudwatch).to receive(:get_metric_statistics) do |args|
      Aws::CloudWatch::Types::GetMetricStatisticsOutput.new(
        datapoints: [Aws::CloudWatch::Types::Datapoint.new(timestamp: args[:end_time], average: 0)]
      )
    end
    harmful = described_class.new(config: config, ses: harmful_ses, cloudwatch: cloudwatch)
    worker = Thread.new { ActiveRecord::Base.connection_pool.with_connection { harmful.call } }
    latest = nil
    begin
      pid = Timeout.timeout(5) { captured.pop }
      expect(ActiveRecord::Base.connection.select_value('SELECT pg_backend_pid()')).not_to eq(pid)
      travel 1.second do
        healthy_ses = instance_double(EmailCampaigns::Ses::Client,
                                      get_account: { 'SendingEnabled' => true, 'EnforcementStatus' => 'HEALTHY' })
        latest = described_class.new(config: config, ses: healthy_ses, cloudwatch: cloudwatch).call
      end
    ensure
      release << true
      worker.join(5) || worker.kill.join
    end
    expect(worker.value.id).to eq(latest.id)
    state = latest.reload
    expect(state).to have_attributes(status: 'healthy', blocked: true)
    expect(state.telemetry).to include('sending_enabled' => true, 'enforcement_status' => 'HEALTHY')
    expect(EmailCampaigns::Reputation::ProviderGate.protection(config: config)[:code]).to eq('provider_blocked')
    audit = EmailReputationAudit.where(provider_key: config.provider_key, action: 'provider_blocked').sole
    expect(audit.snapshot).to include('superseded' => true, 'code' => 'provider_blocked')
  end

  it 'denies release when harm lands after healthy collection but before the final release lock' do
    state = EmailProviderState.create!(provider_key: config.provider_key, status: 'blocked', blocked: true,
                                       observed_at: 1.minute.ago, checked_at: 1.minute.ago)
    actor = create(:user, type: 'SuperAdmin')
    harmful_started = Queue.new
    finish_harmful = Queue.new
    healthy_collected = Queue.new
    return_healthy = Queue.new
    harmful_ses = instance_double(EmailCampaigns::Ses::Client)
    allow(harmful_ses).to receive(:get_account) do
      harmful_started << true
      finish_harmful.pop
      { 'SendingEnabled' => true, 'EnforcementStatus' => 'PROBATION' }
    end
    stub_safe_cloudwatch(cloudwatch)
    harmful_monitor = described_class.new(config: config, ses: harmful_ses, cloudwatch: cloudwatch)
    release_worker = nil
    harmful_worker = Thread.new { ActiveRecord::Base.connection_pool.with_connection { harmful_monitor.call } }
    Timeout.timeout(5) { harmful_started.pop }

    travel 1.second do
      healthy_ses = instance_double(EmailCampaigns::Ses::Client,
                                    get_account: { 'SendingEnabled' => true, 'EnforcementStatus' => 'HEALTHY' })
      real_healthy = described_class.new(config: config, ses: healthy_ses, cloudwatch: cloudwatch)
      release_monitor = pause_monitor_after_collection(real_healthy, healthy_collected, return_healthy)
      releaser = EmailCampaigns::Reputation::ProviderRelease.new(config: config, monitor: release_monitor)
      release_worker = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          releaser.call(actor: actor, reason: 'Reviewed provider remediation')
        rescue CustomExceptions::EmailReputationOverride => e
          e.message
        end
      end
      Timeout.timeout(5) { healthy_collected.pop }
      expect(state.reload).to have_attributes(status: 'healthy', blocked: true, harmful_generation: 0)
      finish_harmful << true
      harmful_worker.join(5) || harmful_worker.kill.join
      expect(state.reload).to have_attributes(status: 'healthy', blocked: true, harmful_generation: 1)
      return_healthy << true
      release_worker.join(5) || release_worker.kill.join
      expect(release_worker.value).to eq('provider_release_denied')
    end
    expect(state.reload).to have_attributes(status: 'healthy', blocked: true, harmful_generation: 1)
    expect(EmailCampaigns::Reputation::ProviderGate.protection(config: config)[:code]).to eq('provider_blocked')
    expect(EmailReputationAudit.where(provider_key: config.provider_key, action: 'provider_released')).to be_empty
  ensure
    finish_harmful << true if defined?(finish_harmful) && harmful_worker&.alive?
    return_healthy << true if defined?(return_healthy) && release_worker&.alive?
    harmful_worker&.join(1)
    release_worker&.join(1)
    actor&.destroy!
  end

  it 'denies release when its own harmful poll finishes late behind newer healthy telemetry' do
    state = EmailProviderState.create!(provider_key: config.provider_key, status: 'blocked', blocked: true,
                                       observed_at: 1.minute.ago, checked_at: 1.minute.ago)
    actor = create(:user, type: 'SuperAdmin')
    harmful_started = Queue.new
    finish_harmful = Queue.new
    harmful_ses = instance_double(EmailCampaigns::Ses::Client)
    allow(harmful_ses).to receive(:get_account) do
      harmful_started << true
      finish_harmful.pop
      { 'SendingEnabled' => true, 'EnforcementStatus' => 'PROBATION' }
    end
    stub_safe_cloudwatch(cloudwatch)
    release_monitor = described_class.new(config: config, ses: harmful_ses, cloudwatch: cloudwatch)
    releaser = EmailCampaigns::Reputation::ProviderRelease.new(config: config, monitor: release_monitor)
    worker = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        releaser.call(actor: actor, reason: 'Reviewed provider remediation')
      rescue CustomExceptions::EmailReputationOverride => e
        e.message
      end
    end
    Timeout.timeout(5) { harmful_started.pop }
    travel 1.second do
      healthy_ses = instance_double(EmailCampaigns::Ses::Client,
                                    get_account: { 'SendingEnabled' => true, 'EnforcementStatus' => 'HEALTHY' })
      described_class.new(config: config, ses: healthy_ses, cloudwatch: cloudwatch).call
    end
    expect(state.reload).to have_attributes(status: 'healthy', blocked: true, harmful_generation: 0)
    finish_harmful << true
    worker.join(5) || worker.kill.join
    expect(worker.value).to eq('provider_release_denied')
    expect(state.reload).to have_attributes(status: 'healthy', blocked: true, harmful_generation: 1)
    expect(EmailCampaigns::Reputation::ProviderGate.protection(config: config)[:code]).to eq('provider_blocked')
    expect(EmailReputationAudit.where(provider_key: config.provider_key, action: 'provider_released')).to be_empty
  ensure
    finish_harmful << true if defined?(finish_harmful) && worker&.alive?
    worker&.join(1)
    actor&.destroy!
  end

  it 'denies release when harm persists after healthy collection but before that collection is persisted' do
    state = EmailProviderState.create!(provider_key: config.provider_key, status: 'blocked', blocked: true,
                                       observed_at: 1.minute.ago, checked_at: 1.minute.ago)
    actor = create(:user, type: 'SuperAdmin')
    collected = Queue.new
    persist_healthy = Queue.new
    stub_safe_cloudwatch(cloudwatch)
    healthy_ses = instance_double(EmailCampaigns::Ses::Client,
                                  get_account: { 'SendingEnabled' => true, 'EnforcementStatus' => 'HEALTHY' })
    release_monitor = described_class.new(config: config, ses: healthy_ses, cloudwatch: cloudwatch)
    allow(release_monitor).to receive(:persist).and_wrap_original do |original, attributes|
      collected << attributes.fetch(:checked_at)
      persist_healthy.pop
      original.call(attributes)
    end
    releaser = EmailCampaigns::Reputation::ProviderRelease.new(config: config, monitor: release_monitor)
    worker = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        releaser.call(actor: actor, reason: 'Reviewed provider remediation')
      rescue CustomExceptions::EmailReputationOverride => e
        e.message
      end
    end
    Timeout.timeout(5) { collected.pop }
    travel 1.second do
      harmful_ses = instance_double(EmailCampaigns::Ses::Client,
                                    get_account: { 'SendingEnabled' => true, 'EnforcementStatus' => 'PROBATION' })
      described_class.new(config: config, ses: harmful_ses, cloudwatch: cloudwatch).call
    end
    expect(state.reload).to have_attributes(status: 'blocked', blocked: true, harmful_generation: 1)
    persist_healthy << true
    worker.join(5) || worker.kill.join
    expect(worker.value).to eq('provider_release_denied')
    expect(state.reload).to have_attributes(status: 'blocked', blocked: true, harmful_generation: 1)
    expect(EmailCampaigns::Reputation::ProviderGate.protection(config: config)[:code]).to eq('provider_blocked')
    expect(EmailReputationAudit.where(provider_key: config.provider_key, action: 'provider_released')).to be_empty
  ensure
    persist_healthy << true if defined?(persist_healthy) && worker&.alive?
    worker&.join(1)
    actor&.destroy!
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
