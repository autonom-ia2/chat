require 'rails_helper'
require 'timeout'

RSpec.describe 'Feedback integration lock protocol', type: :model do
  self.use_transactional_tests = false

  let!(:account) { create(:account) }
  let!(:campaign) { create(:email_campaign, account: account, status: :sending) }
  let!(:recipient) do
    create(:email_campaign_recipient, email_campaign: campaign, status: :sent,
                                      ses_message_id: "feedback-#{campaign.id}", sent_at: 1.hour.ago,
                                      preflight_status: 'valid', preflight_valid_until: 1.hour.from_now)
  end
  let(:payload) { { 'eventType' => 'Complaint', 'mail' => { 'messageId' => recipient.ses_message_id } } }
  let(:workers) { [] }
  let(:enqueue_transactions) { [] }
  let(:safe_cohort) { create_list(:email_campaign_recipient, 49, email_campaign: campaign, status: :sent, sent_at: 1.hour.ago) }

  around do |example|
    with_modified_env('EMAIL_CAMPAIGN_HYGIENE_MODE' => 'enforce', 'EMAIL_REPUTATION_MODE' => 'enforce',
                      'EMAIL_REPUTATION_PROVIDER_MONITOR' => 'false', 'EMAIL_REPUTATION_PROVIDER_BLOCK' => 'false',
                      'EMAIL_REPUTATION_AWS_ACCOUNT_ID' => '') { example.run }
  end

  before do
    allow(EmailCampaigns::Config).to receive(:enabled?).and_return(false)
    allow(EmailCampaigns::ReputationEvaluationJob).to receive(:perform_later) do
      enqueue_transactions << ActiveRecord::Base.connection.open_transactions
    end
    ActiveRecord::Base.connection.execute("SET lock_timeout = '5s'")
  end

  after do
    workers.each { |worker| worker.join(1) || worker.kill.join }
    ActiveRecord::Base.connection.execute('SET lock_timeout TO DEFAULT')
    # Synthetic rows only; immutable suppression/reputation audits retain logical IDs.
    campaigns = EmailCampaign.where(account_id: account.id)
    recipients = EmailCampaignRecipient.where(email_campaign_id: campaigns.select(:id))
    EmailEvent.where(recipient_id: recipients.select(:id)).delete_all
    recipients.delete_all
    campaigns.destroy_all
    EmailSenderIdentity.where(account_id: account.id).destroy_all
    account.destroy!
  end

  # Shared only for the repeated real-session lifecycle/barrier, never for fixture setup.
  def database_worker
    ready = Queue.new
    worker = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        connection.execute("SET lock_timeout = '5s'")
        ready << connection.select_value('SELECT pg_backend_pid()')
        yield
      ensure
        connection.execute('SET lock_timeout TO DEFAULT')
      end
    end
    workers << worker
    pid = Timeout.timeout(5) { ready.pop }
    expect(pid).not_to eq(ActiveRecord::Base.connection.select_value('SELECT pg_backend_pid()'))
    [worker, pid]
  end

  def wait_for_database_block(pid, blocker = ActiveRecord::Base.connection.select_value('SELECT pg_backend_pid()'))
    Timeout.timeout(5) do
      loop do
        break if ActiveRecord::Base.connection.select_value("SELECT #{Integer(blocker)} = ANY(pg_blocking_pids(#{Integer(pid)}))")

        sleep 0.01
      end
    end
  end

  def completed(worker)
    expect(worker.join(10)).to eq(worker)
    worker.value.tap { expect(enqueue_transactions).to all(eq(0)) }
  end

  [true, false].each do |existing_state|
    it "serializes SNS behind admission before recipient locking with existing state=#{existing_state}" do
      state = EmailReputationState.create!(account: account) if existing_state
      preflight = recipient.attributes.slice('preflight_status', 'preflight_valid_until', 'sent_at', 'ses_message_id')
      worker = nil
      account.with_lock do
        state&.lock!
        worker, pid = database_worker { EmailCampaigns::Sns::EventProcessor.new(payload).process }
        wait_for_database_block(pid)
        # Same recipient: old recipient -> state/account order would deadlock here.
        expect(EmailCampaigns::Reputation::Admission.new(campaign).claim!(recipient)).to be(false)
        expect(recipient.reload).to be_sent
      end
      completed(worker)

      expect(recipient.reload).to be_complained
      expect(recipient.attributes.slice(*preflight.keys)).to eq(preflight)
      expect(recipient.email_events.complaint.count).to eq(1)
      expect(EmailReputationState.find_by!(account: account).feedback_version).to eq(1)
      expect(EmailSuppression.suppressed?(account, recipient.email)).to be(true)
    end
  end

  it 'keeps a later admission suppressed when SNS wins the account lock before the final claim' do
    future = create(:email_campaign, account: account, status: :sending)
    pending = create(:email_campaign_recipient, email_campaign: future, email: recipient.email,
                                                preflight_status: 'valid', preflight_valid_until: 1.hour.from_now)
    feedback = admission = nil
    recipient.with_lock do
      feedback, feedback_pid = database_worker { EmailCampaigns::Sns::EventProcessor.new(payload).process }
      wait_for_database_block(feedback_pid)
      admission, admission_pid = database_worker do
        EmailCampaigns::Reputation::Admission.new(EmailCampaign.find(future.id)).claim!(EmailCampaignRecipient.find(pending.id))
      end
      wait_for_database_block(admission_pid, feedback_pid)
    end
    completed(feedback)
    expect(completed(admission)).to be(false)
    expect(recipient.reload).to be_complained
    expect(pending.reload).to have_attributes(status: 'suppressed', sent_at: nil, ses_message_id: nil, preflight_status: 'valid')
    expect(recipient.email_events.complaint.count).to eq(1)
  end

  it 'allows publication/resume to finish before waiting SNS and invalidates that published observation atomically' do
    safe_cohort
    campaign.pause!
    account.update!(internal_attributes: { email_campaigns_paused: { reason: 'synthetic incident' } })
    EmailCampaigns::Reputation::Evaluator.new(account).evaluate!
    observation = EmailCampaigns::Reputation::Observation.new(account.id).collect
    # Freeze the real collection at the boundary immediately before publication.
    allow(EmailCampaigns::Reputation::Observation).to receive(:new).with(account.id).and_return(observation)
    allow(observation).to receive(:collect).and_return(observation)
    worker = nil
    account.with_lock do
      worker, pid = database_worker { EmailCampaigns::Sns::EventProcessor.new(payload).process }
      wait_for_database_block(pid)
      expect(campaign.resume!).to be(true)
    end
    completed(worker)

    expect(campaign.reload).to be_sending
    expect(recipient.reload).to be_complained
    expect(recipient.email_events.complaint.count).to eq(1)
    expect(observation.current?(EmailReputationState.find_by!(account: account))).to be(false)
    expect(EmailSuppression.suppressed?(account, recipient.email)).to be(true)
  end

  it 'rejects a resume collected before SNS committed and preserves its incident and paused campaign' do
    safe_cohort
    campaign.pause!
    account.update!(internal_attributes: { email_campaigns_paused: { reason: 'synthetic incident' } })
    EmailCampaigns::Reputation::Evaluator.new(account).evaluate!
    snapshot = EmailReputationState.find_by!(account: account).trigger_snapshot
    collected = Queue.new
    publish = Queue.new
    allow(EmailCampaigns::Reputation::Observation).to receive(:new).and_wrap_original do |original, id|
      original.call(id).tap do |observation|
        allow(observation).to receive(:collect).and_wrap_original do |collect|
          collect.call.tap do
            collected << true
            publish.pop
          end
        end
      end
    end
    worker, = database_worker do
      EmailCampaign.find(campaign.id).resume!
    rescue CustomExceptions::EmailReputationBlocked => e
      e.protection
    end
    Timeout.timeout(5) { collected.pop }
    EmailCampaigns::Sns::EventProcessor.new(payload).process
    publish << true
    expect(completed(worker)).to include(protection: include(code: 'reputation_evaluation_superseded'))
    expect(campaign.reload).to be_paused
    expect(recipient.reload).to be_complained
    expect(EmailReputationState.find_by!(account: account)).to have_attributes(blocked: true, trigger_snapshot: snapshot, feedback_version: 1)
    expect(EmailReputationAudit.where(account: account, action: 'released')).to be_empty
  ensure
    publish << true
  end

  it 'deduplicates simultaneous SNS replay before event, generation and suppression occurrence writes' do
    EmailReputationState.create!(account: account)
    first = second = nil
    recipient.with_lock do
      first, first_pid = database_worker { EmailCampaigns::Sns::EventProcessor.new(payload).process }
      wait_for_database_block(first_pid)
      second, second_pid = database_worker { EmailCampaigns::Sns::EventProcessor.new(payload).process }
      wait_for_database_block(second_pid, first_pid)
    end
    completed(first)
    completed(second)

    expect(recipient.reload).to be_complained
    expect(recipient.email_events.complaint.count).to eq(1)
    expect(campaign.reload.complained_count).to eq(1)
    expect(EmailReputationState.find_by!(account: account).feedback_version).to eq(1)
    suppression = EmailSuppressionState.find_by!(account: account, email: recipient.email)
    expect(suppression).to have_attributes(active: true, reason: 'complaint', occurrences: 1)
    expect(suppression.email_suppression_events.count).to eq(1)
  end

  it 'creates first state for standalone EmailEvent before its recipient FK and invalidates before enqueue' do
    committed = Queue.new
    enqueue = Queue.new
    allow(EmailCampaigns::Reputation::EvaluationQueue).to receive(:request).and_wrap_original do |original, id|
      committed << true
      enqueue.pop
      original.call(id)
    end
    worker = nil
    account.with_lock do
      worker, pid = database_worker do
        EmailCampaignRecipient.find(recipient.id).email_events.create!(event_type: :complaint)
      end
      wait_for_database_block(pid)
      expect(EmailCampaigns::Reputation::Admission.new(campaign).claim!(recipient)).to be(false)
    end
    Timeout.timeout(5) { committed.pop }
    expect(recipient.email_events.complaint.count).to eq(1)
    expect(EmailReputationState.find_by!(account: account).feedback_version).to eq(1)
    enqueue << true
    expect(completed(worker)).to be_persisted
  ensure
    enqueue << true
  end

  it 'does not acquire account or reputation locks for recipient-held tracking and unsubscribe events' do
    account.with_lock do
      worker, = database_worker do
        fresh = EmailCampaignRecipient.find(recipient.id)
        fresh.with_lock do
          %i[open click unsubscribe].each { |type| fresh.email_events.create!(event_type: type) }
        end
      end
      completed(worker)
    end
    expect(recipient.email_events.count).to eq(3)
    expect(EmailReputationState.find_by(account: account)).to be_nil
  end

  it 'commits delivery-only SNS before counters acquire account/state locks' do
    worker = nil
    account.with_lock do
      worker, pid = database_worker { EmailCampaigns::Sns::EventProcessor.new(payload.merge('eventType' => 'Delivery')).process }
      wait_for_database_block(pid)
      recipient.with_lock { expect(recipient).to be_delivered }
    end
    completed(worker)
    expect(recipient.reload).to be_delivered
    expect(recipient.email_events.delivered.count).to eq(1)
    expect(EmailReputationState.find_by(account: account)).to be_nil
  end
end
