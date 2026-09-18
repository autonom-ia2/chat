require 'rails_helper'

RSpec.describe EmailCampaigns::Maintenance::Dispatch do
  let(:account) { create(:account) }
  let(:suppression_events) { EmailSuppressionEvent.where(account_id: account.id) }
  let(:actor) { create(:user, account: account, type: 'SuperAdmin').becomes(SuperAdmin) }
  let(:parameters) { { reason: 'Outbox verification', idempotency_key: 'outbox_436_01' } }

  it 'retains the run after queue failure and reconciles existing runs only' do
    adapter = EmailCampaigns::ProtectionBackfillJob.queue_adapter
    allow(adapter).to receive(:enqueue).and_raise(ActiveJob::EnqueueError, 'synthetic queue failure')
    run = EmailCampaigns::Maintenance::Start.call(account: account, actor: actor, parameters: parameters)
    expect(run.reload).to have_attributes(status: 'pending', error_code: 'enqueue_failed', error_count: 1)
    allow(adapter).to receive(:enqueue).and_call_original
    travel 6.minutes do
      expect { EmailCampaigns::ProtectionBackfillReconcileJob.perform_now }
        .to have_enqueued_job(EmailCampaigns::ProtectionBackfillJob).with(run.id)
    end
    expect(EmailProtectionMaintenanceRun.count).to eq(1)
  end

  it 'coalesces repeated reconciliation while an enqueue reservation is fresh' do
    run = EmailCampaigns::Maintenance::Start.call(account: account, actor: actor, parameters: parameters)
    expect { 3.times { described_class.call(run.id) } }.not_to have_enqueued_job(EmailCampaigns::ProtectionBackfillJob)
    expect(run.reload.enqueue_attempts).to eq(1)
  end

  it 'bounds repeated lost enqueues instead of retrying forever' do
    run = EmailCampaigns::Maintenance::Start.call(account: account, actor: actor, parameters: parameters)
    3.times do
      travel 6.minutes
      EmailCampaigns::ProtectionBackfillReconcileJob.perform_now
    end
    expect(run.reload).to have_attributes(status: 'failed', error_code: 'enqueue_exhausted', enqueue_attempts: 3)
  ensure
    travel_back
  end

  it 'does not create a run when reconciliation has no work' do
    expect { EmailCampaigns::ProtectionBackfillReconcileJob.perform_now }.not_to change(EmailProtectionMaintenanceRun, :count)
  end

  it 'allows account deletion through the cascade and never retries the deleted run' do
    run = EmailCampaigns::Maintenance::Start.call(account: account, actor: actor, parameters: parameters)
    account.delete
    expect(EmailProtectionMaintenanceRun.exists?(run.id)).to be(false)
    expect { EmailCampaigns::ProtectionBackfillJob.perform_now(run.id) }.not_to have_enqueued_job
    expect { EmailCampaigns::ProtectionBackfillReconcileJob.perform_now }.not_to change(EmailProtectionMaintenanceRun, :count)
  end

  it 'recovers an interrupted expired holder through reconciliation and resumes its committed cursor' do
    campaign = create(:email_campaign, account: account)
    recipient = create(:email_campaign_recipient, email_campaign: campaign)
    event = recipient.email_events.create!(event_type: :complaint)
    run = EmailCampaigns::Maintenance::Start.call(account: account, actor: actor, parameters: parameters)
    run.claim!
    clear_enqueued_jobs
    travel 6.minutes do
      expect { EmailCampaigns::ProtectionBackfillReconcileJob.perform_now }
        .to have_enqueued_job(EmailCampaigns::ProtectionBackfillJob).with(run.id)
      EmailCampaigns::ProtectionBackfillJob.perform_now(run.id)
      expect(run.reload).to have_attributes(event_cursor: event.id, phase: 'legacy', status: 'pending')
      EmailCampaigns::ProtectionBackfillJob.perform_now(run.id)
      expect(run.reload.status).to eq('completed')
    end
    expect(suppression_events.count).to eq(0)
  end

  it 'retains audit without blocking authorized account cleanup after a completed preview' do
    EmailCampaigns::SuppressionRegistry.new(account: account, email: 'synthetic@example.org').record!(
      reason: 'unknown_bounce', source: 'ses', event_key: 'retention-maintenance-436'
    )
    audit = suppression_events.sole
    run = EmailCampaigns::Maintenance::Start.call(account: account, actor: actor, parameters: parameters)
    2.times { EmailCampaigns::ProtectionBackfillJob.perform_now(run.id) }
    expect(run.reload.status).to eq('completed')
    account.destroy!
    expect(EmailProtectionMaintenanceRun.exists?(run.id)).to be(false)
    expect(EmailSuppressionState.where(account_id: account.id)).to be_empty
    expect(audit.reload).to be_readonly
    expect(audit.account).to be_nil
    expect(audit.email_suppression_state).to be_nil
  end
end
