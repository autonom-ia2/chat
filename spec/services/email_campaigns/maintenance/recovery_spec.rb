require 'rails_helper'

RSpec.describe EmailCampaigns::Maintenance::HistoricalProtectionBackfill do # rubocop:disable RSpec/SpecFilePathFormat
  let(:account) { create(:account) }
  let(:suppression_events) { EmailSuppressionEvent.where(account_id: account.id) }
  let(:actor) { create(:user, account: account, type: 'SuperAdmin').becomes(SuperAdmin) }
  let(:campaign) { create(:email_campaign, account: account) }
  let(:recipient) { create(:email_campaign_recipient, email_campaign: campaign) }
  let(:config) { EmailCampaigns::Maintenance::Config.new('EMAIL_CAMPAIGN_PROTECTION_BACKFILL_ENABLED' => 'true') }
  let(:parameters) { { mode: 'apply', confirm: 'apply', reason: 'Recovery verification', idempotency_key: 'recovery_436_01', batch_size: 500 } }
  let(:run) { EmailCampaigns::Maintenance::Start.call(account: account, actor: actor, parameters: parameters, config: config) }

  it 'completes an empty preview without claiming or performing an apply' do
    parameters.delete(:mode)
    parameters.delete(:confirm)
    2.times { described_class.new(run: run.reload, config: config).call }
    expect(run.reload.public_progress).to include('status' => 'completed', 'dry_run' => true)
    expect(run.counts).to be_empty
    expect(EmailSuppression.count).to eq(0)
    expect(suppression_events.count).to eq(0)
    expect do
      EmailCampaigns::Maintenance::Start.call(account: account, actor: actor, config: config,
                                              parameters: parameters.merge(mode: 'apply', confirm: 'apply'))
    end
      .to raise_error(EmailCampaigns::Maintenance::Request::Invalid, 'idempotency_conflict')
  end

  it 'retains a failed preview as a preview and redacts its exception' do
    parameters.delete(:mode)
    parameters.delete(:confirm)
    recipient.email_events.create!(event_type: :complaint)
    allow(EmailCampaigns::Maintenance::Evidence).to receive(:new).and_raise(ArgumentError, 'private provider failure')
    3.times { described_class.new(run: run.reload, config: config).call }
    expect(run.reload.public_progress).to include('status' => 'failed', 'dry_run' => true, 'error_code' => 'batch_failed')
    expect(run.public_progress.to_json).not_to include('private provider failure')
    expect(suppression_events.count).to eq(0)
  end

  it 'does not publish a batch continuation before its outer transaction commits' do
    recipient.email_events.create!(event_type: :complaint)
    persisted = run
    clear_enqueued_jobs
    EmailProtectionMaintenanceRun.transaction do
      described_class.new(run: persisted, config: config).call
      expect(enqueued_jobs).to be_empty
      raise ActiveRecord::Rollback
    end
    expect(enqueued_jobs).to be_empty
    expect(persisted.reload.event_cursor).to eq(0)
    expect(suppression_events.count).to eq(0)
  end

  it 'limits a batch to 500 and excludes subsequent event and legacy inserts from its horizon' do
    501.times { recipient.email_events.create!(event_type: :complaint) }
    initial = run.event_horizon
    late = recipient.email_events.create!(event_type: :unsubscribe)
    legacy = EmailSuppression.create!(account: account, email: 'later@example.org', reason: 'manual')
    described_class.new(run: run, config: config).call
    expect(run.reload.counts['events_processed']).to be_between(1, 500)
    expect(run.event_cursor).to be < initial
    10.times do
      described_class.new(run: run.reload, config: config).call
      break if run.reload.status == 'completed'
    end
    expect(run.reload).to have_attributes(status: 'completed', event_cursor: initial)
    expect(run.counts['events_processed']).to eq(501)
    expect(EmailSuppressionEvent.where(event_key: "unsubscribe:#{late.recipient_id}")).to be_empty
    expect(EmailSuppressionEvent.where(event_key: "historical:email_suppression:#{legacy.id}")).to be_empty
  end

  it 'recovers after a committed partial batch without duplicating audit or losing its cursor' do
    first = recipient.email_events.create!(event_type: :complaint)
    second = recipient.email_events.create!(event_type: :unsubscribe)
    worker = described_class.new(run: run, config: config)
    token = run.claim!
    worker.instance_variable_set(:@token, token)
    worker.send(:process_row, first)
    expect(run.reload.event_cursor).to eq(first.id)
    expect(suppression_events.count).to eq(1)
    travel 3.minutes do
      described_class.new(run: EmailProtectionMaintenanceRun.find(run.id), config: config).call
    end
    expect(run.reload.event_cursor).to eq(second.id)
    expect(run.counts).to include('events_processed' => 2, 'block_records_created' => 2)
    expect(suppression_events.count).to eq(2)
    expect(EmailSuppressionState.sole.occurrences).to eq(2)
  end

  it 'rolls back registry and cursor together if a row transaction is interrupted' do
    first = recipient.email_events.create!(event_type: :complaint)
    token = run.claim!
    worker = described_class.new(run: run, config: config)
    worker.instance_variable_set(:@token, token)
    EmailProtectionMaintenanceRun.transaction do
      worker.send(:process_row, first)
      raise ActiveRecord::Rollback
    end
    expect(run.reload.event_cursor).to eq(0)
    expect(suppression_events.count).to eq(0)
    travel 3.minutes do
      described_class.new(run: run.reload, config: config).call
    end
    expect(run.reload.counts['events_processed']).to eq(1)
    expect(suppression_events.count).to eq(1)
  end

  it 'fences a stale holder after another worker reclaims an expired lease' do
    event = recipient.email_events.create!(event_type: :complaint)
    old = described_class.new(run: run, config: config)
    old.instance_variable_set(:@token, run.claim!)
    expect(EmailProtectionMaintenanceRun.find(run.id).claim!).to be_nil
    travel 3.minutes do
      new_token = EmailProtectionMaintenanceRun.find(run.id).claim!
      expect(new_token).to be_present
      expect(old.send(:process_row, event)).to be(false)
      expect(run.reload.lease_token).to eq(new_token)
    end
    expect(suppression_events.count).to eq(0)
  end

  it 'bounds repeated crashed batches and allows explicit retry without resetting evidence or horizon' do
    recipient.email_events.create!(event_type: :complaint)
    3.times do
      expect(run.claim!).to be_present
      travel 3.minutes
    end
    expect(run.claim!).to be_nil
    expect(run.reload).to have_attributes(status: 'failed', error_code: 'attempts_exhausted')
    horizon = run.event_horizon
    EmailCampaigns::Maintenance::Retry.call(run: run, actor: actor, config: config)
    described_class.new(run: run, config: config).call
    expect(run.reload.event_horizon).to eq(horizon)
    expect(run.counts['events_processed']).to eq(1)
  ensure
    travel_back
  end

  it 'stops an existing apply run when the flag is disabled, before touching protection' do
    recipient.email_events.create!(event_type: :complaint)
    described_class.new(run: run, config: EmailCampaigns::Maintenance::Config.new({})).call
    expect(run.reload).to have_attributes(status: 'failed', error_code: 'apply_disabled', event_cursor: 0)
    expect(suppression_events.count).to eq(0)
  end

  it 'stops an existing apply run when its operator is no longer a persisted SuperAdmin' do
    recipient.email_events.create!(event_type: :complaint)
    persisted_run = run
    actor.update!(type: nil)
    described_class.new(run: persisted_run, config: config).call
    expect(run.reload).to have_attributes(status: 'failed', error_code: 'actor_unavailable', event_cursor: 0)
    expect(suppression_events.count).to eq(0)
  end

  it 'bounds a bad historical row without exposing its value or losing the committed cursor' do
    first = recipient.email_events.create!(event_type: :complaint)
    broken = create(:email_campaign_recipient, email_campaign: campaign)
    broken.email_events.create!(event_type: :unsubscribe)
    broken.update_column(:email, 'private invalid address') # rubocop:disable Rails/SkipsModelValidations -- malformed historical fixture
    3.times do
      described_class.new(run: run.reload, config: config).call
      travel 6.minutes
    end
    expect(run.reload).to have_attributes(status: 'failed', error_code: 'batch_failed', error_count: 3, event_cursor: first.id)
    expect(run.counts['events_processed']).to eq(1)
    expect(suppression_events.count).to eq(1)
    expect(run.public_progress.to_json).not_to include('private invalid address')
  ensure
    travel_back
  end

  [true, false].each do |dry_run|
    it "stops an abandoned dry_run=#{dry_run} when the operator loses account access" do
      recipient.email_events.create!(event_type: :complaint)
      if dry_run
        parameters.delete(:mode)
        parameters.delete(:confirm)
      end
      persisted = run
      persisted.claim!
      actor.account_users.where(account: account).delete_all
      travel 6.minutes do
        EmailCampaigns::ProtectionBackfillReconcileJob.perform_now
        described_class.new(run: persisted.reload, config: config).call
      end
      expect(persisted.reload).to have_attributes(status: 'failed', error_code: 'actor_unavailable', event_cursor: 0)
      expect(suppression_events.count).to eq(0)
    end
  end
end
