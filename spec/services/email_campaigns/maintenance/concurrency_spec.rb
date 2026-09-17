require 'rails_helper'

# Parent only: requires isolated PostgreSQL, committed records and two connections.
RSpec.describe 'Protection backfill lease concurrency', type: :model do
  self.use_transactional_tests = false

  let!(:account) { create(:account) }
  let!(:actor) { create(:user, account: account, type: 'SuperAdmin').becomes(SuperAdmin) }
  let!(:run) do
    EmailProtectionMaintenanceRun.create!(account: account, actor_id: actor.id, reason: 'Concurrent lease verification',
                                          idempotency_key: 'concurrency_436_01',
                                          event_horizon: 0, legacy_horizon: 0, next_dispatch_at: 1.hour.from_now)
  end

  after do
    EmailProtectionMaintenanceRun.where(account: account).delete_all
    EmailSuppressionEvent.where(account_id: account.id).delete_all
    EmailSuppressionState.where(account: account).delete_all
    EmailSuppression.where(account: account).delete_all
    account.destroy!
    actor.destroy!
  end

  it 'grants a lease to exactly one simultaneous worker' do
    ready = Queue.new
    start = Queue.new
    threads = Array.new(2) do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          contender = EmailProtectionMaintenanceRun.find(run.id)
          ready << true
          start.pop
          contender.claim!
        end
      end
    end
    2.times { ready.pop }
    2.times { start << true }
    tokens = threads.filter_map(&:value)
    expect(tokens.size).to eq(1)
    expect(run.reload.lease_token).to eq(tokens.sole)
    expect(run.attempts).to eq(1)
  ensure
    threads&.each { |thread| thread.join(5) }
  end

  it 'coalesces concurrent starts with the same tenant and request key' do
    ready = Queue.new
    start = Queue.new
    parameters = { reason: 'Synthetic concurrent preview', idempotency_key: 'concurrent_start_436' }
    threads = Array.new(2) do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          EmailCampaigns::Maintenance::Start.call(account: account, actor: actor, parameters: parameters).id
        end
      end
    end
    2.times { ready.pop }
    2.times { start << true }
    expect(threads.map(&:value).uniq.size).to eq(1)
    expect(EmailProtectionMaintenanceRun.where(account: account, idempotency_key: parameters[:idempotency_key]).count).to eq(1)
  ensure
    threads&.each { |thread| thread.join(5) }
  end

  it 'serializes separate runs replaying the same legacy key through the actual registry' do
    legacy = EmailSuppression.create!(account: account, email: 'concurrent@example.org', reason: 'provider_suppression')
    attributes = { account: account, actor_id: actor.id, dry_run: false, phase: 'legacy', reason: 'Synthetic concurrent apply',
                   event_horizon: 0, legacy_horizon: legacy.id, next_dispatch_at: 1.hour.from_now }
    contenders = Array.new(2) do |index|
      EmailProtectionMaintenanceRun.create!(**attributes, idempotency_key: "concurrent_registry_436_#{index}")
    end
    ready = Queue.new
    start = Queue.new
    config = EmailCampaigns::Maintenance::Config.new('EMAIL_CAMPAIGN_PROTECTION_BACKFILL_ENABLED' => 'true')
    threads = contenders.map do |contender|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          EmailCampaigns::Maintenance::HistoricalProtectionBackfill.new(run: contender, config: config).call
        end
      end
    end
    2.times { ready.pop }
    2.times { start << true }
    threads.each(&:value)
    expect(contenders.map { |contender| contender.reload.status }).to eq(%w[completed completed])
    expect(contenders.sum { |contender| contender.counts.fetch('legacy_rows_mirrored', 0) }).to eq(1)
    expect(contenders.sum { |contender| contender.counts.fetch('duplicate_legacy_rows', 0) }).to eq(1)
    expect(EmailSuppressionEvent.where(account_id: account.id).count).to eq(1)
    expect(EmailSuppressionState.find_by!(account: account)).to have_attributes(reason: 'provider_suppression', active: true, occurrences: 1)
  ensure
    threads&.each { |thread| thread.join(5) }
  end

  it 'keeps duplicate initial processing jobs read-only and completes one bounded preview' do
    ready = Queue.new
    start = Queue.new
    threads = Array.new(2) do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          EmailCampaigns::ProtectionBackfillJob.perform_now(run.id)
        end
      end
    end
    2.times { ready.pop }
    2.times { start << true }
    threads.each(&:value)
    EmailCampaigns::ProtectionBackfillJob.perform_now(run.id)
    expect(run.reload).to have_attributes(status: 'completed', dry_run: true, event_cursor: 0, legacy_cursor: 0)
    expect(EmailSuppressionEvent.where(account_id: account.id)).to be_empty
    expect(EmailSuppressionState.where(account_id: account.id)).to be_empty
  ensure
    threads&.each { |thread| thread.join(5) }
  end

  it 'admits only one concurrent retry and charges one persistent request budget' do
    run.fail_run!('batch_failed')
    ready = Queue.new
    start = Queue.new
    threads = Array.new(2) do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          contender = EmailProtectionMaintenanceRun.find(run.id)
          ready << true
          start.pop
          begin
            EmailCampaigns::Maintenance::Retry.call(run: contender, actor: actor)
            'accepted'
          rescue EmailCampaigns::Maintenance::Request::Invalid => e
            e.message
          end
        end
      end
    end
    2.times { ready.pop }
    2.times { start << true }
    expect(threads.map(&:value).sort).to eq(%w[accepted run_not_failed])
    expect(run.reload).to have_attributes(status: 'pending', retry_count: 1)
  ensure
    threads&.each { |thread| thread.join(5) }
  end

  it 'allows concurrent preview and apply without giving the preview a write path' do
    legacy = EmailSuppression.create!(account: account, email: 'preview-race@example.org', reason: 'unsubscribe', created_at: 2.years.ago)
    original = legacy.attributes
    contenders = [true, false].map do |dry_run|
      EmailProtectionMaintenanceRun.create!(account: account, actor_id: actor.id, dry_run: dry_run, phase: 'legacy',
                                            reason: 'Preview apply race', idempotency_key: "preview_apply_436_#{dry_run}",
                                            event_horizon: 0, legacy_horizon: legacy.id, next_dispatch_at: 1.hour.from_now)
    end
    ready = Queue.new
    start = Queue.new
    config = EmailCampaigns::Maintenance::Config.new('EMAIL_CAMPAIGN_PROTECTION_BACKFILL_ENABLED' => 'true')
    threads = contenders.map do |contender|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          EmailCampaigns::Maintenance::HistoricalProtectionBackfill.new(run: contender, config: config).call
        end
      end
    end
    2.times { ready.pop }
    2.times { start << true }
    threads.each(&:value)
    expect(contenders.map { |contender| contender.reload.status }).to eq(%w[completed completed])
    expect(contenders.first.counts).to eq('legacy_rows_processed' => 1)
    expect(EmailSuppressionEvent.where(account_id: account.id).sole.metadata['maintenance_run_id']).to eq(contenders.last.id)
    expect(legacy.reload.attributes).to eq(original)
  ensure
    threads&.each { |thread| thread.join(5) }
  end
end
