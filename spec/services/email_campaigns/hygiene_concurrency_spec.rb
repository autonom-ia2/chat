require 'rails_helper'
require 'timeout'

# Requires the parent's isolated PostgreSQL test database. Separate committed records
# are necessary for real connection/thread races; transactional fixtures hide them.
RSpec.describe 'Email hygiene concurrency', type: :model do
  self.use_transactional_tests = false

  let!(:account) { create(:account) }

  after do
    campaigns = EmailCampaign.where(account_id: account.id)
    recipients = EmailCampaignRecipient.where(email_campaign_id: campaigns.select(:id))
    EmailEvent.where(recipient_id: recipients.select(:id)).delete_all
    recipients.delete_all
    campaigns.delete_all
    EmailSenderIdentity.where(account_id: account.id).delete_all
    EmailSuppressionEvent.where(account_id: account.id).delete_all
    EmailSuppressionState.where(account_id: account.id).delete_all
    EmailSuppression.where(account_id: account.id).delete_all
    account.destroy!
  end

  # Two real connections, with committed fixtures. PR439's Account -> campaign ->
  # recipient worker holds Account until PostgreSQL confirms the PR438 writer is
  # blocked by it. The former recipient -> state-FK path then forms a real cycle.
  def overlap_account_first_worker(recipient)
    worker_connection = ActiveRecord::Base.connection
    writer_pid = Queue.new
    writer = nil
    account.with_lock do
      worker_connection.execute("SET LOCAL lock_timeout = '10s'")
      recipient.email_campaign.lock!
      writer = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          writer_pid << connection.raw_connection.backend_pid
          yield
        end
      end
      wait_for_blocked_writer(worker_connection, writer_pid.pop(timeout: 10), writer)
      recipient.lock!
    end
    writer.value
  ensure
    writer&.join(15) || writer&.kill&.join
  end

  def wait_for_blocked_writer(connection, pid, writer)
    Timeout.timeout(10) do
      loop do
        break if connection.select_value("SELECT pg_backend_pid() = ANY(pg_blocking_pids(#{Integer(pid)}))")

        raise 'writer finished without the required lock overlap' unless writer.alive?

        sleep 0.01
      end
    end
  end

  it 'persists PR438 signed opt-out with generic 200 while an account-first PR439 worker is holding Account' do
    allow(EmailCampaigns::Config).to receive(:enabled?).and_return(true)
    campaign = create(:email_campaign, account: account)
    recipient = create(:email_campaign_recipient, email_campaign: campaign, status: :sent)
    token = EmailCampaigns::Unsubscribe::Token.wrap(EmailCampaigns::Unsubscribe::Token.encode(recipient))
    session = overlap_account_first_worker(recipient) do
      request = ActionDispatch::Integration::Session.new(Rails.application)
      request.post("/email_campaigns/u/#{token}")
      request
    end
    expect([session.response.status, session.response.body]).to eq([200, EmailCampaigns::UnsubscribeController::CONFIRMATION_TEXT])
    expect(recipient.reload).to be_unsubscribed
    expect(EmailSuppression.find_by!(account: account, email: recipient.email).reason).to eq('unsubscribe')
    expect(EmailSuppressionState.find_by!(account: account, email: recipient.email).reason).to eq('unsubscribe')
    expect(recipient.email_events.where(event_type: :unsubscribe).count).to eq(1)
    expect(EmailSuppressionEvent.where(account: account, reason: 'unsubscribe').count).to eq(1)
  end

  { 'UnsubscribedRecipient' => %w[unsubscribe unsubscribed], 'General' => %w[hard_bounce bounced],
    'Complaint' => %w[complaint complained] }.each do |subtype, (reason, status)|
    it "persists PR438 SNS #{reason} while an account-first PR439 worker is holding Account" do
      campaign = create(:email_campaign, account: account)
      recipient = create(:email_campaign_recipient, email_campaign: campaign, status: :sent, ses_message_id: 'overlap-ses')
      event = { 'eventType' => subtype == 'Complaint' ? 'Complaint' : 'Bounce', 'mail' => { 'messageId' => recipient.ses_message_id },
                'bounce' => { 'bounceType' => 'Permanent', 'bounceSubType' => subtype } }
      overlap_account_first_worker(recipient) { EmailCampaigns::Sns::EventProcessor.new(event).process }
      expect(EmailSuppression.find_by!(account: account, email: recipient.email).reason).to eq(reason)
      expect(EmailSuppressionState.find_by!(account: account, email: recipient.email).reason).to eq(reason)
      expect(EmailSuppressionEvent.where(account: account, reason: reason).count).to eq(1)
      expect(recipient.reload.status).to eq(status)
    end
  end

  it 'serializes simultaneous first insert and replay using the tenant/email unique key' do
    ready = Queue.new
    start = Queue.new
    threads = Array.new(3) do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          EmailCampaigns::SuppressionRegistry.new(account: account, email: 'Same@Example.org').record!(
            reason: 'temporary_failure', source: 'ses', event_key: 'same-event'
          )
        end
      end
    end
    3.times { ready.pop }
    3.times { start << true }
    results = threads.map(&:value)
    expect(results.count(&:duplicate)).to eq(2)
    expect(EmailSuppressionState.where(account: account).count).to eq(1)
    expect(EmailSuppressionState.find_by!(account: account).occurrences).to eq(1)
    expect(EmailSuppressionEvent.where(account: account).count).to eq(1)
    expect(EmailSuppression.suppressed?(account, 'same@example.org')).to be false
  end

  it 'counts one SNS bounce under parallel replay, without reaching the quarantine threshold' do
    campaign = create(:email_campaign, account: account)
    recipient = create(:email_campaign_recipient, email_campaign: campaign, status: :sent, ses_message_id: 'parallel-ses')
    event = { 'eventType' => 'Bounce', 'mail' => { 'messageId' => recipient.ses_message_id },
              'bounce' => { 'bounceType' => 'Transient', 'bounceSubType' => 'MailboxFull' } }
    start = Queue.new
    threads = Array.new(3) do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          start.pop
          EmailCampaigns::Sns::EventProcessor.new(event).process
        end
      end
    end
    3.times { start << true }
    threads.each(&:value)
    expect(recipient.email_events.where(event_type: :bounce).count).to eq(1)
    expect(campaign.reload.bounced_count).to eq(1)
    expect(EmailSuppressionState.find_by!(account: account).occurrences).to eq(1)
    expect(EmailSuppression.suppressed?(account, recipient.email)).to be false
  end

  it 'allows only one delivery claimant' do
    campaign = create(:email_campaign, account: account, status: :sending)
    recipient = create(:email_campaign_recipient, email_campaign: campaign)
    start = Queue.new
    threads = Array.new(2) do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          start.pop
          EmailCampaigns::DeliveryClaim.new(campaign).claim(EmailCampaignRecipient.find(recipient.id))
        end
      end
    end
    2.times { start << true }
    expect(threads.map(&:value).sort).to eq(%i[claimed skipped])
    expect(recipient.reload).to be_sent
  end

  it 'coalesces simultaneous preflight scheduling and consumes a queued token only once' do
    allow(EmailCampaigns::Config).to receive(:enabled?).and_return(true)
    campaign = create(:email_campaign, account: account)
    create(:email_campaign_recipient, email_campaign: campaign)
    start = Queue.new
    threads = Array.new(2) do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          start.pop
          EmailCampaigns::PreflightLease.new(EmailCampaign.find(campaign.id)).acquire
        end
      end
    end
    2.times { start << true }
    queued = threads.filter_map(&:value)
    expect(queued.size).to eq(1)
    threads = Array.new(2) do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          start.pop
          EmailCampaigns::PreflightLease.new(EmailCampaign.find(campaign.id)).claim(*queued.first)
        end
      end
    end
    2.times { start << true }
    expect(threads.filter_map(&:value).size).to eq(1)
  end
end
