require 'rails_helper'

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
