require 'rails_helper'

RSpec.describe EmailCampaigns::Reputation::Evaluator do # rubocop:disable RSpec/SpecFilePathFormat -- real session regressions
  self.use_transactional_tests = false

  let!(:account) { create(:account) }
  let!(:identity) { EmailSenderIdentity.create!(account: account, domain: 'concurrency.example.com', status: :verified) }
  let!(:campaign) do
    EmailCampaign.create!(account: account, sender_identity: identity, name: 'Synthetic concurrency',
                          subject: 'Synthetic concurrency test', body_html: '<p>Synthetic isolated test</p>', status: :sending)
  end
  let(:policy) { EmailCampaigns::Reputation::Policy.new('EMAIL_REPUTATION_MODE' => 'enforce') }
  let(:captured) { Queue.new }
  let(:release) { Queue.new }

  before do
    allow(EmailCampaigns::Reputation::ProviderGate).to receive(:protection).and_return(nil)
    allow(EmailCampaigns::Reputation::Metrics).to receive(:new).and_wrap_original do |original, *args|
      collector = original.call(*args)
      allow(collector).to receive(:call).and_wrap_original do |collect|
        result = collect.call
        if Thread.current[:slow_reputation_collection]
          captured << ActiveRecord::Base.connection.select_value('SELECT pg_backend_pid()')
          release.pop
        end
        result
      end
      collector
    end
  end

  after do
    # Scoped synthetic cleanup only. Append-only audits deliberately retain logical IDs.
    EmailEvent.where(recipient_id: campaign.email_campaign_recipients.select(:id)).delete_all
    campaign.email_campaign_recipients.delete_all
    campaign.destroy!
    identity.destroy!
    account.destroy!
  end

  it 'collects 50k sends without blocking an unrelated JSON update or admission before publication' do
    connection = ActiveRecord::Base.connection
    connection.execute(<<~SQL.squish)
      INSERT INTO email_campaign_recipients (email_campaign_id, email, status, sent_at, created_at, updated_at)
      SELECT #{campaign.id}, 'synthetic-' || n || '@example.com', 1, NOW(), NOW(), NOW()
      FROM generate_series(1, 50000) n
    SQL
    connection.execute(<<~SQL.squish)
      INSERT INTO email_events (recipient_id, event_type, occurred_at, payload, created_at, updated_at)
      SELECT id, 3, NOW(), '{"bounce":{"bounceType":"Permanent"}}'::jsonb, NOW(), NOW()
      FROM email_campaign_recipients WHERE email_campaign_id = #{campaign.id} ORDER BY id
    SQL
    pending = campaign.email_campaign_recipients.create!(email: 'pending@example.com')
    worker = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        Thread.current[:slow_reputation_collection] = true
        described_class.new(Account.find(account.id), policy: policy).evaluate!
      end
    end
    begin
      pid = Timeout.timeout(10) { captured.pop }
      expect(connection.select_value('SELECT pg_backend_pid()')).not_to eq(pid)
      Timeout.timeout(3) do
        Account.find(account.id).update!(internal_attributes: { concurrent_note: 'preserved' })
        expect(EmailCampaigns::Reputation::Admission.new(campaign).claim!(pending)).to be(true)
      end
    ensure
      release << true
      worker.join(15) || worker.kill.join
    end
    expect(worker.value).to include(blocked: true)
    expect(account.reload.internal_attributes).to include('concurrent_note' => 'preserved', 'email_campaigns_paused' => be_present)
    result_sizes = []
    allow(connection).to receive(:select_all).and_wrap_original do |original, *args, **options|
      original.call(*args, **options).tap { |result| result_sizes << result.rows.size }
    end
    expect(EmailCampaigns::Reputation::Metrics.new(account.id).harmful_feedback_fingerprint).to match(/\A[0-9a-f]{64}\z/)
    expect(result_sizes).to eq([1])
  end

  it 'discards a slow safe resume after a later generation publishes new risk' do
    100.times { |i| campaign.email_campaign_recipients.create!(email: "safe#{i}@example.com", sent_at: 1.hour.ago) }
    account.update!(internal_attributes: { email_campaigns_paused: { reason: 'previous incident' } })
    worker = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        Thread.current[:slow_reputation_collection] = true
        described_class.new(Account.find(account.id), policy: policy).resume!
      end
    end
    begin
      pid = Timeout.timeout(10) { captured.pop }
      expect(ActiveRecord::Base.connection.select_value('SELECT pg_backend_pid()')).not_to eq(pid)
      campaign.email_campaign_recipients.order(:id).first(5).each do |recipient|
        recipient.email_events.create!(event_type: :bounce, payload: { bounce: { bounceType: 'Permanent' } })
      end
      newest = described_class.new(account, policy: policy).evaluate!
      expect(newest).to include(blocked: true, resume_allowed: false)
    ensure
      release << true
      worker.join(15) || worker.kill.join
    end
    expect(worker.value).to include(resume_allowed: false, protection: include(code: 'reputation_evaluation_superseded'))
    expect(EmailReputationState.find_by!(account: account).current_metrics['permanent']).to eq(5)
    expect(account.reload.internal_attributes['email_campaigns_paused']).to be_present
    expect(EmailReputationAudit.where(account: account, action: 'released')).to be_empty
  end

  # rubocop:disable RSpec/MultipleExpectations -- barrier, durable incident and lease invariants across three cycles
  it 'blocks before the next claim through three feedback-superseded harmful evaluations and keeps following up' do
    accepted = Array.new(100) do |index|
      campaign.email_campaign_recipients.create!(email: "stream#{index}@example.com", sent_at: 1.hour.ago, status: :sent)
    end
    described_class.new(account, policy: policy).evaluate!
    state = EmailReputationState.find_by!(account: account)
    published = state.attributes.slice('current_metrics', 'policy', 'evaluated_at', 'evaluated_feedback_version')
    accepted.first(10).each do |row|
      row.email_events.create!(event_type: :bounce, payload: { bounce: { bounceType: 'Permanent' } })
    end
    snapshot = nil
    3.times do |cycle|
      token = state.reload.evaluation_lease_token
      worker = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          Thread.current[:slow_reputation_collection] = true
          described_class.new(Account.find(account.id), policy: policy).evaluate!
        end
      end
      begin
        pid = Timeout.timeout(5) { captured.pop }
        expect(ActiveRecord::Base.connection.select_value('SELECT pg_backend_pid()')).not_to eq(pid)
        accepted.fetch(10 + cycle).email_events.create!(event_type: :bounce, payload: { bounce: { bounceType: 'Transient' } })
      ensure
        release << true
        worker.join(5) || worker.kill.join
      end
      expect(worker.value).to include(blocked: true, resume_allowed: false,
                                      protection: include(code: 'reputation_evaluation_superseded'))
      expect(state.reload.attributes.slice(*published.keys)).to eq(published)
      expect(state.feedback_version).to eq(11 + cycle)
      snapshot ||= state.trigger_snapshot.deep_dup
      expect(state.trigger_snapshot).to eq(snapshot)
      expect(snapshot).to include('superseded' => true, 'feedback_version' => 10)
      expect(snapshot.dig('metrics', 'permanent_ratio')).to eq(0.1)
      expect(account.reload.internal_attributes['email_campaigns_paused']).to be_present
      pending = campaign.email_campaign_recipients.create!(email: "denied#{cycle}@example.com")
      campaign.update!(status: :sending) # Exercise reputation again, not just the previous campaign pause.
      expect(EmailCampaigns::DeliveryClaim.new(campaign).claim(pending)).to eq(:paused)
      expect(pending.reload).to be_pending
      expect do
        EmailCampaigns::Reputation::EvaluationQueue.finish(account.id, token)
      end.to have_enqueued_job(EmailCampaigns::ReputationEvaluationJob).with(account.id, kind_of(String))
      expect(state.reload.evaluation_lease_token).not_to eq(token)
    end
    expect(EmailReputationAudit.where(account: account, action: 'paused').pluck(:snapshot)).to eq([snapshot])
    token = state.reload.evaluation_lease_token
    expect(described_class.new(account, policy: policy).evaluate!).to include(blocked: true)
    expect(state.reload.evaluated_feedback_version).to eq(state.feedback_version)
    EmailCampaigns::Reputation::EvaluationQueue.finish(account.id, token)
    expect(state.reload.evaluation_lease_token).to be_nil
  end

  # rubocop:enable RSpec/MultipleExpectations

  it 'invalidates a pre-feedback observation before the committed event reaches its enqueue callback' do
    recipient = campaign.email_campaign_recipients.create!(email: 'commit-barrier@example.com', sent_at: 1.hour.ago)
    observation = EmailCampaigns::Reputation::Observation.new(account.id).collect
    committed = Queue.new
    enqueue = Queue.new
    allow(EmailCampaigns::Reputation::EvaluationQueue).to receive(:request).and_wrap_original do |original, id|
      committed << ActiveRecord::Base.connection.select_value('SELECT pg_backend_pid()')
      enqueue.pop
      original.call(id)
    end
    worker = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        EmailCampaignRecipient.find(recipient.id).email_events.create!(event_type: :complaint)
      end
    end
    begin
      pid = Timeout.timeout(5) { committed.pop }
      expect(ActiveRecord::Base.connection.select_value('SELECT pg_backend_pid()')).not_to eq(pid)
      expect(EmailEvent.where(recipient_id: recipient.id, event_type: :complaint)).to exist
      state = EmailReputationState.find_by!(account: account)
      expect(observation.current?(state)).to be(false)
      expect(state.feedback_version).to eq(1)
    ensure
      enqueue << true
      worker.join(5) || worker.kill.join
    end
    expect(worker.value).to be_persisted
  end

  it 'keeps the actual campaign resume collection outside the account lock' do
    100.times { |i| campaign.email_campaign_recipients.create!(email: "resume#{i}@example.com", sent_at: 1.hour.ago) }
    campaign.update!(status: :paused)
    account.update!(internal_attributes: { email_campaigns_paused: { reason: 'previous incident' } })
    worker = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        Thread.current[:slow_reputation_collection] = true
        EmailCampaign.find(campaign.id).resume!
      end
    end
    begin
      pid = Timeout.timeout(10) { captured.pop }
      expect(ActiveRecord::Base.connection.select_value('SELECT pg_backend_pid()')).not_to eq(pid)
      Timeout.timeout(3) do
        fresh = Account.find(account.id)
        fresh.update!(internal_attributes: fresh.internal_attributes.merge('during_resume' => 'retained'))
      end
    ensure
      release << true
      worker.join(15) || worker.kill.join
    end
    worker.value
    expect(campaign.reload).to be_sending
    expect(account.reload.internal_attributes).to eq('during_resume' => 'retained')
  end
end
