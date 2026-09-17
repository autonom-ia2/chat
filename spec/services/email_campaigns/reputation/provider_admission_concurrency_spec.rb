require 'rails_helper'
require 'timeout'
require 'aws-sdk-cloudwatch'

RSpec.describe EmailCampaigns::DeliveryClaim do # rubocop:disable RSpec/SpecFilePathFormat -- provider publication versus final admission
  self.use_transactional_tests = false

  let!(:account) { create(:account) }
  let!(:campaign) { create(:email_campaign, account: account, status: :sending) }
  let!(:recipient) do
    create(:email_campaign_recipient, email_campaign: campaign, preflight_status: 'valid',
                                      preflight_checked_at: Time.current, preflight_valid_until: 1.hour.from_now)
  end
  let(:provider_account) { SecureRandom.random_number(10**12).to_s.rjust(12, '0') }
  let(:config) { EmailCampaigns::Reputation::ProviderConfig.new }
  let(:ses) { instance_double(EmailCampaigns::Ses::Client) }
  let(:monitor) { EmailCampaigns::Reputation::ProviderMonitor.new(config: config, ses: ses) }
  let(:workers) { [] }
  let(:connection) { ActiveRecord::Base.connection }
  let(:main_pid) { connection.select_value('SELECT pg_backend_pid()') }

  around do |example|
    with_modified_env('EMAIL_REPUTATION_PROVIDER_MONITOR' => 'true', 'EMAIL_REPUTATION_AWS_ACCOUNT_ID' => provider_account,
                      'EMAIL_REPUTATION_PROVIDER_BLOCK' => 'false', 'EMAIL_CAMPAIGN_HYGIENE_DNS_ENABLED' => 'false') { example.run }
  end

  before do
    allow(ses).to receive(:get_account) do
      raise 'collection inside transaction' if ActiveRecord::Base.connection.transaction_open?

      { 'SendingEnabled' => false, 'EnforcementStatus' => 'SHUTDOWN' }
    end
  end

  after do
    workers.each { |worker| worker.join(5) || worker.kill.join }
    EmailProviderState.where(provider_key: config.provider_key).delete_all
    campaign.email_campaign_recipients.delete_all
    identity = campaign.sender_identity
    campaign.destroy!
    identity.destroy!
    account.destroy!
  end

  [false, true].each do |existing_provider|
    it "denies the final claim after monitor commits its block (existing provider: #{existing_provider})" do
      EmailProviderState.create!(provider_key: config.provider_key, status: 'healthy', observed_at: Time.current) if existing_provider
      entering = Queue.new
      owner = main_pid
      allow(monitor).to receive(:update_observation!).and_wrap_original do |original, *args|
        original.call(*args)
        workers << Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do |session|
            entering << session.select_value('SELECT pg_backend_pid()')
            described_class.new(EmailCampaign.find(campaign.id)).claim(EmailCampaignRecipient.find(recipient.id))
          end
        end
        pid = Timeout.timeout(5) { entering.pop }
        expect(pid).not_to eq(owner)
        Timeout.timeout(5) do
          loop do
            break if connection.select_value("SELECT #{owner.to_i} = ANY(pg_blocking_pids(#{pid.to_i}))")

            Thread.pass
          end
        end
        expect(recipient.reload).to be_pending
      end
      monitor.call
      expect(workers.first.join(5)).to eq(workers.first)
      expect(workers.first.value).to eq(:paused)
      expect(recipient.reload).to be_pending
      expect(campaign.reload.pause_reason['code']).to eq('provider_blocked')
      expect(EmailProviderState.where(provider_key: config.provider_key).count).to eq(1)
    end
  end

  it 'makes monitor wait when the final claim already owns provider, then rejects the next claim' do # rubocop:disable RSpec/MultipleExpectations -- both serial orders
    provider = EmailProviderState.create!(provider_key: config.provider_key, status: 'healthy', observed_at: Time.current)
    collected = Queue.new
    owner = main_pid
    decision = EmailCampaigns::PreflightDecision.new
    allow(EmailCampaigns::PreflightDecision).to receive(:new).and_return(decision)
    allow(ses).to receive(:get_account) do
      session = ActiveRecord::Base.connection
      expect(session.transaction_open?).to be(false)
      collected << session.select_value('SELECT pg_backend_pid()')
      { 'SendingEnabled' => false, 'EnforcementStatus' => 'SHUTDOWN' }
    end
    allow(decision).to receive(:call).and_wrap_original do |original, row|
      workers << Thread.new { ActiveRecord::Base.connection_pool.with_connection { monitor.call } }
      pid = Timeout.timeout(5) { collected.pop }
      expect(pid).not_to eq(owner)
      Timeout.timeout(5) do
        loop do
          break if connection.select_value("SELECT #{owner.to_i} = ANY(pg_blocking_pids(#{pid.to_i}))")

          Thread.pass
        end
      end
      expect(provider.reload.blocked).to be(false)
      expect(recipient.reload).to be_pending
      original.call(row)
    end
    expect(described_class.new(campaign).claim(recipient)).to eq(:claimed)
    expect(workers.first.join(5)).to eq(workers.first)
    expect(workers.first.value.reload.blocked).to be(true)
    expect(recipient.reload).to be_sent
    pending = create(:email_campaign_recipient, email_campaign: campaign)
    expect(described_class.new(campaign).claim(pending)).to eq(:paused)
    expect(pending.reload).to be_pending
  end

  it 'keeps SES and CloudWatch collection and actual dispatch outside database transactions' do
    depths = []
    allow(ses).to receive(:get_account) do
      depths << connection.open_transactions
      { 'SendingEnabled' => true, 'EnforcementStatus' => 'HEALTHY' }
    end
    cloudwatch = instance_double(Aws::CloudWatch::Client)
    allow(cloudwatch).to receive(:get_metric_statistics) do |args|
      depths << connection.open_transactions
      Aws::CloudWatch::Types::GetMetricStatisticsOutput.new(
        datapoints: [Aws::CloudWatch::Types::Datapoint.new(timestamp: args[:end_time], average: 0)]
      )
    end
    EmailCampaigns::Reputation::ProviderMonitor.new(config: config, ses: ses, cloudwatch: cloudwatch).call
    sender = instance_double(EmailCampaigns::Ses::Sender)
    allow(EmailCampaigns::Ses::Sender).to receive(:new).and_return(sender)
    allow(sender).to receive(:deliver) do
      depths << connection.open_transactions
      'synthetic-accepted'
    end
    allow(EmailCampaigns::Config).to receive(:enabled?).and_return(true)
    allow(EmailCampaigns::Unsubscribe::Token).to receive(:url).and_return('https://example.org/unsubscribe')
    engine = EmailCampaigns::DeliveryEngine.new(campaign)
    allow(engine).to receive(:sleep)
    engine.perform
    expect(recipient.reload.ses_message_id).to eq('synthetic-accepted')
    expect(depths).to eq([0, 0, 0, 0])
  end
end
