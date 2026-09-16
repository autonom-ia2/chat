require 'rails_helper'
require 'timeout'

RSpec.describe 'Integrated claim and cancellation concurrency', type: :model do
  self.use_transactional_tests = false

  let!(:account) { create(:account) }
  let!(:campaign) { create(:email_campaign, account: account, status: :sending) }
  let!(:recipient) do
    create(:email_campaign_recipient, email_campaign: campaign, preflight_status: 'valid', preflight_valid_until: 1.hour.from_now)
  end

  around do |example|
    with_modified_env('EMAIL_CAMPAIGN_HYGIENE_MODE' => 'enforce', 'EMAIL_REPUTATION_MODE' => 'shadow',
                      'EMAIL_REPUTATION_PROVIDER_MONITOR' => 'false', 'EMAIL_REPUTATION_PROVIDER_BLOCK' => 'false',
                      'EMAIL_REPUTATION_AWS_ACCOUNT_ID' => '') { example.run }
  end

  before do
    EmailReputationState.create!(account: account)
    allow(EmailCampaigns::Config).to receive(:enabled?).and_return(true)
    allow(EmailCampaigns::Unsubscribe::Token).to receive(:url).and_return('https://example.org/u/synthetic')
    allow(EmailCampaigns::Tracking::Injector).to receive(:new).and_return(
      instance_double(EmailCampaigns::Tracking::Injector, perform: '<p>Synthetic</p>')
    )
  end

  after do
    # Only this example's synthetic rows; append-only reputation audits retain logical IDs.
    EmailEvent.where(recipient_id: campaign.email_campaign_recipients.select(:id)).delete_all
    campaign.email_campaign_recipients.delete_all
    campaign.destroy!
    EmailSenderIdentity.where(account_id: account.id).destroy_all
    account.destroy!
  end

  it 'lets cancellation serialize before a competing final claim on a distinct database session' do
    ready = Queue.new
    worker = nil
    # Observe the actual mutation boundary, after cancel! has acquired its own
    # locks. Never manufacture a campaign -> account order in the test itself.
    allow(campaign).to receive(:update!).and_wrap_original do |update, *attributes|
      worker = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          ready << connection.select_value('SELECT pg_backend_pid()')
          EmailCampaigns::Reputation::Admission.new(EmailCampaign.find(campaign.id)).claim!(EmailCampaignRecipient.find(recipient.id))
        end
      end
      pid = Timeout.timeout(5) { ready.pop }
      connection = ActiveRecord::Base.connection
      parent_pid = connection.select_value('SELECT pg_backend_pid()')
      expect(parent_pid).not_to eq(pid)
      Timeout.timeout(5) do
        sleep 0.01 until connection.select_value("SELECT #{parent_pid} = ANY(pg_blocking_pids(#{pid}))")
      end
      update.call(*attributes)
    end
    campaign.cancel!
    expect(Timeout.timeout(5) { worker.value }).to be(false)
    expect(recipient.reload).to be_suppressed
    expect(recipient.sent_at).to be_nil
    expect(campaign.reload).to be_canceled
  ensure
    worker&.join(5) || worker&.kill&.join
  end

  it 'dispatches outside row transactions, rejects a duplicate worker and preserves acceptance after concurrent cancel' do
    next_recipient = create(:email_campaign_recipient, email_campaign: campaign,
                                                       preflight_status: 'valid', preflight_valid_until: 1.hour.from_now)
    entered = Queue.new
    release = Queue.new
    sender = instance_double(EmailCampaigns::Ses::Sender)
    allow(EmailCampaigns::Ses::Sender).to receive(:new).and_return(sender)
    allow(sender).to receive(:deliver) do
      connection = ActiveRecord::Base.connection
      entered << [connection.select_value('SELECT pg_backend_pid()'), connection.open_transactions]
      release.pop
      'accepted-in-flight'
    end
    worker = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        EmailCampaigns::DeliveryEngine.new(EmailCampaign.find(campaign.id)).perform
      end
    end
    begin
      pid, open_transactions = Timeout.timeout(5) { entered.pop }
      expect(open_transactions).to eq(0)
      expect(ActiveRecord::Base.connection.select_value('SELECT pg_backend_pid()')).not_to eq(pid)
      expect(EmailCampaigns::DeliveryEngine.new(EmailCampaign.find(campaign.id)).perform).to be(false)
      Timeout.timeout(5) { campaign.cancel! }
    ensure
      release << true
      worker.join(5) || worker.kill.join
    end
    worker.value
    expect(sender).to have_received(:deliver).once
    expect(recipient.reload).to have_attributes(ses_message_id: 'accepted-in-flight', sent_at: be_present)
    expect(next_recipient.reload).to be_suppressed
    expect(campaign.reload).to be_canceled
  end
end
