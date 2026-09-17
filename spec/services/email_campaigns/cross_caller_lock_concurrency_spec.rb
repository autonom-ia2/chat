require 'rails_helper'
require 'timeout'

RSpec.describe 'Email cross-caller lock closure', type: :model do
  self.use_transactional_tests = false

  let!(:account) { create(:account) }
  let!(:campaign) { create(:email_campaign, account: account, status: :sending) }
  let!(:recipient) do
    create(:email_campaign_recipient, email_campaign: campaign, preflight_status: 'valid', preflight_valid_until: 1.hour.from_now)
  end
  let(:workers) { [] }
  let(:token) { EmailCampaigns::Unsubscribe::Token.wrap(EmailCampaigns::Unsubscribe::Token.encode(recipient)) }

  around do |example|
    with_modified_env('EMAIL_CAMPAIGN_HYGIENE_MODE' => 'enforce', 'EMAIL_CAMPAIGN_HYGIENE_DNS_ENABLED' => 'false',
                      'EMAIL_REPUTATION_MODE' => 'shadow', 'EMAIL_REPUTATION_PROVIDER_MONITOR' => 'false',
                      'EMAIL_REPUTATION_PROVIDER_BLOCK' => 'false', 'EMAIL_REPUTATION_AWS_ACCOUNT_ID' => '') { example.run }
  end

  before do
    allow(EmailCampaigns::Config).to receive(:enabled?).and_return(true)
    allow(EmailCampaigns::ReputationEvaluationJob).to receive(:perform_later)
    ActiveRecord::Base.connection.execute("SET lock_timeout = '5s'")
  end

  after do
    workers.each { |worker| worker.join(1) || worker.kill.join }
    ActiveRecord::Base.connection.execute('SET lock_timeout TO DEFAULT')
    campaigns = EmailCampaign.where(account_id: account.id)
    recipients = EmailCampaignRecipient.where(email_campaign_id: campaigns.select(:id))
    EmailEvent.where(recipient_id: recipients.select(:id)).delete_all
    EmailCampaignImportIssue.where(email_campaign_id: campaigns.select(:id)).delete_all
    EmailCampaignImport.where(email_campaign_id: campaigns.select(:id)).destroy_all
    recipients.delete_all
    campaigns.destroy_all
    EmailSuppression.where(account_id: account.id).delete_all
    EmailSenderIdentity.where(account_id: account.id).destroy_all
    account.destroy!
  end

  # These helpers share only real connection/barrier handling, never lock substitutes.
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

  def wait_for_block(pid, blocker = ActiveRecord::Base.connection.select_value('SELECT pg_backend_pid()'))
    Timeout.timeout(5) do
      loop do
        break if ActiveRecord::Base.connection.select_value("SELECT #{Integer(blocker)} = ANY(pg_blocking_pids(#{Integer(pid)}))")

        sleep 0.01
      end
    end
  end

  def completed(worker)
    expect(worker.join(10)).to eq(worker)
    worker.value
  end

  it 'makes the full signed unsubscribe endpoint wait for account before touching the claimed recipient' do
    worker = nil
    account.with_lock do
      worker, pid = database_worker do
        session = ActionDispatch::Integration::Session.new(Rails.application)
        session.post("/email_campaigns/u/#{token}")
        session.response.status
      end
      wait_for_block(pid)
      expect(EmailCampaigns::Reputation::Admission.new(campaign).claim!(recipient)).to be(true)
    end
    expect(completed(worker)).to eq(200)
    expect(recipient.reload).to be_unsubscribed
    expect(recipient.email_events.unsubscribe.count).to eq(1)
    expect(EmailSuppression.find_by!(account: account, email: recipient.email).reason).to eq('unsubscribe')
    # A receipt arriving after the verified opt-out must retain its permanent status.
    EmailCampaigns::DeliveryEngine.new(campaign).send(:persist_sent!, recipient, 'accepted-before-optout')
    expect(recipient.reload).to have_attributes(status: 'unsubscribed', ses_message_id: 'accepted-before-optout', sent_at: be_present)
  end

  it 'serializes link opt-out with feedback and prevents a later send to the same address' do # rubocop:disable RSpec/MultipleExpectations
    recipient.update!(status: :sent, ses_message_id: "link-feedback-#{recipient.id}", sent_at: 1.hour.ago)
    future = create(:email_campaign, account: account, sender_identity: campaign.sender_identity, status: :sending)
    pending = create(:email_campaign_recipient, email_campaign: future, email: recipient.email,
                                                preflight_status: 'valid', preflight_valid_until: 1.hour.from_now)
    unsubscribe = feedback = nil
    recipient.with_lock do
      unsubscribe, unsubscribe_pid = database_worker do
        session = ActionDispatch::Integration::Session.new(Rails.application)
        session.post("/email_campaigns/u/#{token}")
        session.response.status
      end
      wait_for_block(unsubscribe_pid)
      feedback, feedback_pid = database_worker do
        EmailCampaigns::Sns::EventProcessor.new('eventType' => 'Complaint', 'mail' => { 'messageId' => recipient.ses_message_id }).process
      end
      wait_for_block(feedback_pid, unsubscribe_pid)
    end
    expect(completed(unsubscribe)).to eq(200)
    completed(feedback)
    expect(recipient.reload).to be_unsubscribed
    expect(recipient.email_events.unsubscribe.count).to eq(1)
    expect(recipient.email_events.complaint.count).to eq(1)
    expect(EmailReputationState.find_by!(account: account).feedback_version).to eq(1)
    expect(EmailSuppressionState.find_by!(account: account, email: recipient.email)).to have_attributes(reason: 'unsubscribe', expires_at: nil)
    expect(EmailCampaigns::Reputation::Admission.new(future).claim!(pending)).to be(false)
    expect(pending.reload).to have_attributes(status: 'suppressed', sent_at: nil)
  end

  it 'takes account before an existing registry row, allowing feedback to finish without a sibling cycle' do
    registry = EmailCampaigns::SuppressionRegistry.new(account: account, email: recipient.email, campaign: campaign)
    registry.record!(reason: 'unknown_bounce', source: 'ses', event_key: 'initial')
    recipient.update!(status: :sent, ses_message_id: "registry-#{recipient.id}", sent_at: 1.hour.ago)
    worker = nil
    account.with_lock do
      worker, pid = database_worker do
        EmailCampaigns::SuppressionRegistry.new(account: account, email: recipient.email).block!(
          reason: 'unsubscribe', source: 'link', event_key: 'standalone'
        )
      end
      wait_for_block(pid)
      EmailCampaigns::Sns::EventProcessor.new('eventType' => 'Complaint', 'mail' => { 'messageId' => recipient.ses_message_id }).process
    end
    completed(worker)
    expect(EmailSuppressionState.find_by!(account: account, email: recipient.email).reason).to eq('unsubscribe')
    expect(EmailSuppression.find_by!(account: account, email: recipient.email).reason).to eq('unsubscribe')
  end

  it 'commits an active atomic import before counters wait on a concurrent claim account lock' do
    import = campaign.email_campaign_imports.create!
    import.source_file.attach(io: StringIO.new("name,email\nImported,imported@example.org\n"), filename: 'list.csv', content_type: 'text/csv')
    inserted = Queue.new
    finish_import = Queue.new
    parse_transactions = []
    allow(CampaignImports::Parser).to receive(:new).and_wrap_original do |original, *args, **keywords|
      parse_transactions << ActiveRecord::Base.connection.open_transactions
      original.call(*args, **keywords)
    end
    allow(EmailCampaignRecipient).to receive(:insert_all!).and_wrap_original do |original, *args|
      original.call(*args).tap do
        inserted << true
        finish_import.pop
      end
    end
    importing, import_pid = database_worker { EmailCampaigns::RecipientImportJob.perform_now(import.id) }
    Timeout.timeout(5) { inserted.pop }
    expect(import.reload).to be_processing
    claiming, claim_pid = database_worker do
      EmailCampaigns::Reputation::Admission.new(EmailCampaign.find(campaign.id)).claim!(EmailCampaignRecipient.find(recipient.id))
    end
    wait_for_block(claim_pid, import_pid)
    finish_import << true
    expect(completed(claiming)).to be(true)
    completed(importing)
    expect(import.reload).to be_completed
    expect(parse_transactions).to eq([0])
    expect(campaign.reload.recipients_count).to eq(2)
    expect(recipient.reload).to be_sent
  ensure
    finish_import << true
  end

  it 'rejects an active import at admission before its first insert or parsing acquires any child lock' do
    import = campaign.email_campaign_imports.create!
    import.source_file.attach(io: StringIO.new("name,email\nImported,imported@example.org\n"), filename: 'list.csv', content_type: 'text/csv')
    parsing = Queue.new
    proceed = Queue.new
    allow(CampaignImports::Parser).to receive(:new).and_wrap_original do |original, *args, **keywords|
      parsing << ActiveRecord::Base.connection.open_transactions
      proceed.pop
      original.call(*args, **keywords)
    end
    importing, = database_worker { EmailCampaigns::RecipientImportJob.perform_now(import.id) }
    expect(Timeout.timeout(5) { parsing.pop }).to eq(0)
    expect(import.reload).to be_processing
    expect(EmailCampaigns::Reputation::Admission.new(campaign).claim!(recipient)).to be(false)
    expect(recipient.reload).to be_pending
    proceed << true
    completed(importing)
    expect(import.reload).to be_completed
  ensure
    proceed << true
  end

  it 'publishes preflight evidence under ordered locks before a waiting claim can consume it' do
    recipient.update!(preflight_status: 'unchecked', preflight_valid_until: nil)
    lease = EmailCampaigns::PreflightLease.new(campaign).acquire
    preflight = instance_double(EmailCampaigns::AddressPreflight)
    observations = []
    allow(EmailCampaigns::AddressPreflight).to receive(:new).and_return(preflight)
    allow(preflight).to receive(:call) do
      observations << ActiveRecord::Base.connection.open_transactions
      { status: 'valid', reason_code: 'mx', valid_until: 1.hour.from_now }
    end
    checking = claiming = nil
    recipient.with_lock do
      checking, checking_pid = database_worker { EmailCampaigns::RecipientPreflightJob.perform_now(campaign.id, *lease) }
      wait_for_block(checking_pid)
      claiming, claiming_pid = database_worker do
        EmailCampaigns::Reputation::Admission.new(EmailCampaign.find(campaign.id)).claim!(EmailCampaignRecipient.find(recipient.id))
      end
      wait_for_block(claiming_pid, checking_pid)
    end
    completed(checking)
    expect(completed(claiming)).to be(true)
    expect(observations).to eq([0])
    expect(recipient.reload).to have_attributes(status: 'sent', preflight_status: 'valid')
  end

  it 'defers counter aggregation and parent locking until the outer recipient transaction commits' do
    observations = []
    allow(campaign).to receive(:counter_attributes).and_wrap_original do |original|
      observations << ActiveRecord::Base.connection.open_transactions
      original.call
    end
    EmailCampaignRecipient.transaction do
      recipient.with_lock do
        recipient.update!(status: :suppressed)
        campaign.refresh_counters!
      end
      expect(observations).to eq([])
      expect(campaign.reload.suppressed_count).to eq(0)
    end
    expect(observations).to eq([0])
    expect(campaign.reload.suppressed_count).to eq(1)
  end

  it 'discards deferred counter publication when the outer transaction rolls back' do
    expect(campaign).not_to receive(:counter_attributes)
    EmailCampaignRecipient.transaction do
      recipient.with_lock do
        recipient.update!(status: :suppressed)
        campaign.refresh_counters!
      end
      raise ActiveRecord::Rollback
    end
    expect(recipient.reload).to be_pending
    expect(campaign.reload.suppressed_count).to eq(0)
  end

  it 'does not overwrite committed opt-out when tracking loaded a stale recipient beforehand' do
    stale = EmailCampaignRecipient.find(recipient.id)
    session = ActionDispatch::Integration::Session.new(Rails.application)
    session.post("/email_campaigns/u/#{token}")
    expect(session.response.status).to eq(200)
    recorder = EmailCampaigns::Tracking::EventRecorder.new(stale)
    recorder.record_open
    recorder.record_click('https://example.org/synthetic')
    expect(recipient.reload).to be_unsubscribed
    expect(recipient.email_events.opens.count).to eq(1)
    expect(recipient.email_events.clicks.count).to eq(1)
    expect(EmailSuppression.find_by!(account: account, email: recipient.email).reason).to eq('unsubscribe')
  end
end
