require 'rails_helper'

RSpec.describe 'Preflight lock and commit closure', type: :model do
  self.use_transactional_tests = false

  let!(:campaign) { create(:email_campaign, status: :sending) }
  let!(:recipient) do
    create(:email_campaign_recipient, email_campaign: campaign, preflight_status: 'valid', preflight_valid_until: 1.hour.from_now)
  end

  around do |example|
    with_modified_env('EMAIL_CAMPAIGN_HYGIENE_MODE' => 'enforce', 'EMAIL_CAMPAIGN_HYGIENE_DNS_ENABLED' => 'false') { example.run }
  end

  before { allow(EmailCampaigns::Config).to receive(:enabled?).and_return(true) }

  after do
    EmailCampaignImportIssue.where(email_campaign_id: campaign.id).delete_all
    EmailCampaignImport.where(email_campaign_id: campaign.id).delete_all
    campaign.email_campaign_recipients.delete_all
    campaign.destroy!
    campaign.sender_identity.destroy!
    campaign.account.destroy!
  end

  # One pass must preserve fencing across all of these boundaries, including recovery.
  it 'invalidates old evidence atomically, processes bounded batches and recovers an expired recheck at its durable cursor' do # rubocop:disable RSpec/MultipleExpectations
    create_list(:email_campaign_recipient, 100, email_campaign: campaign, preflight_status: 'valid', preflight_valid_until: 1.hour.from_now)
    untouched = campaign.email_campaign_recipients.order(:id).last
    lease = EmailCampaigns::PreflightLease.new(campaign)
    queued = lease.acquire(recheck: true)
    expect(recipient.reload.preflight_status).to eq('valid')
    expect(EmailCampaigns::PreflightDecision.new.call(recipient)[:allowed]).to be(false)
    expect(EmailCampaigns::PreflightDecision.new.campaign_allowed?(campaign.reload)).to be(false)
    EmailCampaigns::RecipientPreflightJob.perform_now(campaign.id, *queued)
    cursor = campaign.reload.preflight_cursor
    expect(cursor).to be_positive
    expect(campaign.preflight_summary).to include('rechecking' => true)
    expect(untouched.reload.preflight_status).to eq('valid')
    expect(EmailCampaigns::PreflightDecision.new.call(untouched)[:allowed]).to be(false)
    expect(campaign.email_campaign_recipients.where(preflight_status: 'unknown').count).to eq(100)
    travel 6.minutes
    recovered = lease.acquire
    expect(recovered.last).to eq(cursor)
    EmailCampaigns::RecipientPreflightJob.perform_now(campaign.id, *recovered)
    expect(campaign.reload.preflight_summary).to eq('unknown' => 101)
    expect(campaign.preflight_lease_token).to be_nil
  end

  it 'fences a late result and summary after a newer recheck owns the lease' do
    lease = EmailCampaigns::PreflightLease.new(campaign)
    running = lease.claim(*lease.acquire(recheck: true)).first
    travel 6.minutes
    queued = lease.acquire
    current = lease.claim(*queued).first
    job = EmailCampaigns::RecipientPreflightJob.new
    job.instance_variable_set(:@lease, lease)
    result = { status: 'invalid', reason_code: 'invalid_domain', valid_until: 1.hour.from_now }
    config = EmailCampaigns::HygieneConfig.new
    job.send(:persist_result, recipient, result, running, config)
    expect(recipient.reload.preflight_status).to eq('valid')
    expect(lease.advance(running, recipient.id)).to be_nil
    expect(campaign.reload.preflight_lease_token).to eq(current)
    expect(campaign.preflight_summary).to include('rechecking' => true)
    job.send(:persist_result, recipient, result, current, config)
    expect(recipient.reload.preflight_status).to eq('invalid')
  end

  it 'locks account then state then campaign for acquisition, claim and result publication, and aggregates outside transactions' do
    EmailReputationState.create!(account: campaign.account)
    locks = []
    aggregates = []
    subscriber = lambda do |*args|
      sql = args.last.fetch(:sql)
      locks << sql[/FROM "([^"]+)"/, 1] if sql.include?('FOR UPDATE')
      aggregates << ActiveRecord::Base.connection.open_transactions if sql.include?('GROUP BY') && sql.include?('preflight_status')
    end
    ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record') do
      queued = EmailCampaigns::PreflightLease.new(campaign).acquire(recheck: true)
      EmailCampaigns::RecipientPreflightJob.perform_now(campaign.id, *queued)
    end
    expect(locks.each_slice(3).to_a).to all(eq(%w[accounts email_reputation_states email_campaigns]))
    expect(locks.size).to eq(12)
    expect(aggregates).to eq([0])
  end

  it 'recovers and completes technical preflight progress despite unrelated invalid legacy campaign content' do
    campaign.update_columns(subject: nil, body_html: nil) # rubocop:disable Rails/SkipsModelValidations
    expect(campaign).not_to be_valid
    queued = EmailCampaigns::PreflightLease.new(campaign).acquire(recheck: true)
    expect(queued).to be_present
    travel 6.minutes
    expect(EmailCampaigns::RecipientPreflightJob.enqueue(campaign.id)).to be(true)
    EmailCampaigns::RecipientPreflightJob.perform_now(*enqueued_jobs.last.fetch(:args))
    expect(campaign.reload).to have_attributes(subject: nil, body_html: nil, status: 'sending', preflight_lease_token: nil)
    expect(campaign.preflight_summary).to eq('unknown' => 1)
  end

  it 'enqueues a queued token only after the outer transaction commits and not after rollback' do # rubocop:disable RSpec/MultipleExpectations
    enqueues = []
    allow(EmailCampaigns::RecipientPreflightJob).to receive(:perform_later) do |*args|
      enqueues << [args, ActiveRecord::Base.connection.open_transactions]
    end
    EmailCampaign.transaction do
      expect(EmailCampaigns::RecipientPreflightJob.enqueue(campaign.id, recheck: true)).to be(true)
      expect(enqueues).to eq([])
      raise ActiveRecord::Rollback
    end
    expect(enqueues).to eq([])
    EmailCampaign.transaction do
      expect(EmailCampaigns::RecipientPreflightJob.enqueue(campaign.id, recheck: true)).to be(true)
      expect(enqueues).to eq([])
    end
    expect(enqueues.size).to eq(1)
    expect(enqueues.first.last).to eq(0)
    expect(enqueues.first.first).to eq([campaign.id, campaign.reload.preflight_lease_token, 0])
  end

  it 'retains the committed import transition across reload without enqueueing before the outer commit' do
    import = campaign.email_campaign_imports.create!
    enqueues = []
    allow(EmailCampaigns::RecipientPreflightJob).to receive(:enqueue) do |id|
      enqueues << [id, ActiveRecord::Base.connection.open_transactions]
    end
    EmailCampaignImport.transaction do
      import.update!(status: :completed)
      import.reload
      expect(enqueues).to eq([])
    end
    expect(enqueues).to eq([[campaign.id, 0]])
  end

  it 'does not enqueue preflight for a rolled-back completion' do
    import = campaign.email_campaign_imports.create!
    expect(EmailCampaigns::RecipientPreflightJob).not_to receive(:enqueue)
    EmailCampaignImport.transaction do
      import.update!(status: :completed)
      raise ActiveRecord::Rollback
    end
    expect(import.reload).to be_queued
  end

  it 'queues scheduled delivery only after its surrounding transition commits' do
    campaign.update!(status: :scheduled, scheduled_at: 1.minute.ago)
    enqueues = []
    allow(EmailCampaigns::DeliveryJob).to receive(:perform_later) do |id|
      enqueues << [id, ActiveRecord::Base.connection.open_transactions]
    end
    EmailCampaign.transaction do
      EmailCampaigns::Scheduler.new.send(:start, campaign)
      expect(campaign.reload).to be_sending
      expect(enqueues).to eq([])
    end
    expect(enqueues).to eq([[campaign.id, 0]])
  end
end
