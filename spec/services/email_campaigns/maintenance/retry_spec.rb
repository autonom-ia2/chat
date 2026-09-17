require 'rails_helper'

RSpec.describe EmailCampaigns::Maintenance::Retry do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, type: 'SuperAdmin').becomes(SuperAdmin) }
  let(:config) { EmailCampaigns::Maintenance::Config.new('EMAIL_CAMPAIGN_PROTECTION_BACKFILL_ENABLED' => 'true') }
  let(:parameters) { { reason: 'Synthetic recovery', idempotency_key: 'retry_436_01' } }
  let(:run) { EmailCampaigns::Maintenance::Start.call(account: account, actor: actor, parameters: parameters, config: config) }

  it 'publishes a retry only after commit and preserves failed state on outer rollback' do
    run.fail_run!('batch_failed')
    before = run.reload.attributes
    clear_enqueued_jobs
    EmailProtectionMaintenanceRun.transaction do
      described_class.call(run: run, actor: actor, config: config)
      expect(enqueued_jobs).to be_empty
      raise ActiveRecord::Rollback
    end
    expect(enqueued_jobs).to be_empty
    expect(run.reload.attributes).to eq(before)
    expect do
      EmailProtectionMaintenanceRun.transaction do
        described_class.call(run: run, actor: actor, config: config)
        expect(enqueued_jobs).to be_empty
      end
    end
      .to have_enqueued_job(EmailCampaigns::ProtectionBackfillJob).with(run.id)
    expect(run.reload.error_count).to eq(before['error_count'])
  end

  it 'recovers an explicit retry whose publication failed using the durable reconciler' do
    run.fail_run!('batch_failed')
    adapter = EmailCampaigns::ProtectionBackfillJob.queue_adapter
    allow(adapter).to receive(:enqueue).and_raise(ActiveJob::EnqueueError, 'private queue error')
    described_class.call(run: run, actor: actor, config: config)
    expect(run.reload).to have_attributes(status: 'pending', error_code: 'enqueue_failed', error_count: 2)
    allow(adapter).to receive(:enqueue).and_call_original
    travel 6.minutes do
      expect { EmailCampaigns::ProtectionBackfillReconcileJob.perform_now }
        .to have_enqueued_job(EmailCampaigns::ProtectionBackfillJob).with(run.id)
    end
  end

  it 'requires the original persisted SuperAdmin and a failed run' do
    expect { described_class.call(run: run, actor: actor, config: config) }
      .to raise_error(EmailCampaigns::Maintenance::Request::Invalid, 'run_not_failed')
    run.fail_run!('batch_failed')
    other = create(:user, account: account, type: 'SuperAdmin').becomes(SuperAdmin)
    expect { described_class.call(run: run, actor: other, config: config) }
      .to raise_error(EmailCampaigns::Maintenance::Request::Invalid, 'actor_mismatch')
    ordinary = create(:user, account: account, role: :administrator)
    expect { described_class.call(run: run, actor: ordinary, config: config) }.to raise_error(Pundit::NotAuthorizedError)
    actor.update!(type: nil)
    expect { described_class.call(run: run, actor: actor, config: config) }.to raise_error(Pundit::NotAuthorizedError)
    expect(run.reload.status).to eq('failed')
  end

  it 'reconciles a retry interrupted after commit and before its callback could publish' do
    run.fail_run!('batch_failed')
    clear_enqueued_jobs
    allow(EmailCampaigns::Maintenance::Dispatch).to receive(:call)
    described_class.call(run: run, actor: actor, config: config)
    expect(run.reload.status).to eq('pending')
    expect(enqueued_jobs).to be_empty
    allow(EmailCampaigns::Maintenance::Dispatch).to receive(:call).and_call_original
    expect { EmailCampaigns::ProtectionBackfillReconcileJob.perform_now }
      .to have_enqueued_job(EmailCampaigns::ProtectionBackfillJob).with(run.id)
  end

  it 'rechecks the apply flag without changing the cursor, history or mode' do
    parameters[:mode] = 'apply'
    parameters[:confirm] = 'apply'
    run.fail_run!('apply_disabled')
    before = run.reload.attributes
    expect { described_class.call(run: run, actor: actor, config: EmailCampaigns::Maintenance::Config.new({})) }
      .to raise_error(EmailCampaigns::Maintenance::Request::Invalid, 'apply_disabled')
    expect(run.reload.attributes).to eq(before)
  end

  it 'caps explicit requests across failures without resetting the evidence ceiling' do
    horizon = run.event_horizon
    3.times do
      run.fail_run!('batch_failed')
      described_class.call(run: run, actor: actor, config: config)
    end
    run.fail_run!('batch_failed')
    before = run.reload.attributes
    expect { described_class.call(run: run, actor: actor, config: config) }
      .to raise_error(EmailCampaigns::Maintenance::Request::Invalid, 'retries_exhausted')
    expect(run.reload.attributes).to eq(before)
    expect(run).to have_attributes(retry_count: 3, event_horizon: horizon)
  end

  it 'rejects retry after membership removal despite an authenticated stale actor' do
    run.fail_run!('batch_failed')
    actor.account_users.where(account: account).delete_all
    expect { described_class.call(run: run, actor: actor, config: config) }.to raise_error(Pundit::NotAuthorizedError)
    expect(run.reload).to have_attributes(status: 'failed', retry_count: 0)
  end
end
