require 'rails_helper'
require 'timeout'

RSpec.describe EmailCampaigns::DirectInbox::TickJob do # rubocop:disable RSpec/SpecFilePathFormat -- transition concurrency regressions
  self.use_transactional_tests = false

  let!(:inbox) { create(:channel_email).inbox }
  let!(:campaign) do
    create(:email_campaign, account: inbox.account, delivery_mode: :direct_inbox, sender_inbox: inbox,
                            status: :scheduled, scheduled_at: 1.minute.ago)
  end
  let!(:recipient) { create(:email_campaign_recipient, email_campaign: campaign) }
  let(:engine) { instance_double(EmailCampaigns::DirectInbox::DeliveryEngine) }
  let(:workers) { [] }
  let(:engine_transactions) { [] }

  before do
    allow(EmailCampaigns::Config).to receive(:enabled?).and_return(true)
    allow(EmailCampaigns::DirectInbox::DeliveryEngine).to receive(:new).and_return(engine)
    allow(engine).to receive(:tick) do
      engine_transactions << ActiveRecord::Base.connection.open_transactions
    end
  end

  after do
    workers.each { |worker| worker.join(1) || worker.kill.join }
    account = inbox.account
    campaign.email_campaign_recipients.delete_all
    campaign.destroy!
    EmailSenderIdentity.where(account_id: account.id).destroy_all
    # The application removes hours asynchronously; this nontransactional fixture
    # must remove only its own rows before deleting the inbox, or later model specs
    # encounter orphaned hours through WorkingHour.today.
    WorkingHour.where(inbox_id: inbox.id).delete_all
    inbox.channel.destroy!
    inbox.destroy! if inbox.persisted?
    account.destroy!
  end

  # Force the job's initial read before the competing write, then observe the SQL wait.
  # This also exercises the old UPDATE race: reload sees the uncommitted scheduled row.
  def start_tick_before_competing_write # rubocop:disable Metrics/AbcSize, Metrics/MethodLength -- one real-session barrier lifecycle
    read = Queue.new
    proceed = Queue.new
    allow(EmailCampaign).to receive(:find_by).with(id: campaign.id).and_wrap_original do |original, **arguments|
      original.call(**arguments).tap do
        read << ActiveRecord::Base.connection.select_value('SELECT pg_backend_pid()')
        proceed.pop
      end
    end
    worker = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        connection.execute("SET lock_timeout = '5s'")
        described_class.perform_now(campaign.id)
      ensure
        connection.execute('SET lock_timeout TO DEFAULT')
      end
    end
    workers << worker
    pid = Timeout.timeout(5) { read.pop }
    expect(pid).not_to eq(ActiveRecord::Base.connection.select_value('SELECT pg_backend_pid()'))
    [worker, pid, proceed]
  end

  def wait_for_transition_lock(pid)
    blocker = ActiveRecord::Base.connection.select_value('SELECT pg_backend_pid()')
    Timeout.timeout(5) do
      loop do
        break if ActiveRecord::Base.connection.select_value("SELECT #{Integer(blocker)} = ANY(pg_blocking_pids(#{Integer(pid)}))")

        sleep 0.01
      end
    end
  end

  %i[cancel pause].each do |action|
    it "does not overwrite a concurrent #{action} or tick/requeue after losing the transition" do
      worker = nil
      campaign.with_delivery_lock do
        worker, pid, proceed = start_tick_before_competing_write
        campaign.public_send("#{action}!")
        proceed << true
        wait_for_transition_lock(pid)
      end
      expect(worker.join(10)).to eq(worker)
      worker.value
      expect(campaign.reload.status).to eq(action == :cancel ? 'canceled' : 'paused')
      expect(recipient.reload.status).to eq(action == :cancel ? 'suppressed' : 'pending')
      expect(engine).not_to have_received(:tick)
      expect(enqueued_jobs.select { |job| job[:job] == described_class }).to be_empty
    end
  end

  %i[queued processing].each do |status|
    it "does not promote or tick when an import becomes #{status} after the initial read" do
      worker = nil
      campaign.with_delivery_lock do
        worker, pid, proceed = start_tick_before_competing_write
        campaign.email_campaign_imports.create!(status: status)
        proceed << true
        wait_for_transition_lock(pid)
      end
      expect(worker.join(10)).to eq(worker)
      worker.value
      expect(campaign.reload).to be_scheduled
      expect(recipient.reload).to be_pending
      expect(engine).not_to have_received(:tick)
      expect(enqueued_jobs.select { |job| job[:job] == described_class }).to be_empty
    end
  end

  it 'leaves an existing sending campaign unchanged and does not tick during an active import' do
    campaign.update!(status: :sending)
    campaign.email_campaign_imports.create!(status: :processing)
    described_class.perform_now(campaign.id)
    expect(campaign.reload).to be_sending
    expect(engine).not_to have_received(:tick)
  end

  it 'promotes a due scheduled campaign and calls the existing engine outside the transition transaction' do
    described_class.perform_now(campaign.id)
    expect(campaign.reload).to be_sending
    expect(engine).to have_received(:tick).once
    expect(engine_transactions).to eq([0])
  end

  it 'keeps processing an existing sending campaign even when its old schedule is in the future' do
    campaign.update!(status: :sending, scheduled_at: 1.hour.from_now)
    described_class.perform_now(campaign.id)
    expect(campaign.reload).to be_sending
    expect(engine).to have_received(:tick).once
    expect(engine_transactions).to eq([0])
  end

  it 'does not start a future scheduled campaign from an early or stale job' do
    campaign.update!(scheduled_at: 1.hour.from_now)
    described_class.perform_now(campaign.id)
    expect(campaign.reload).to be_scheduled
    expect(engine).not_to have_received(:tick)
  end

  it 'does not start a scheduled campaign without a schedule' do
    campaign.update!(scheduled_at: nil)
    described_class.perform_now(campaign.id)
    expect(campaign.reload).to be_scheduled
    expect(engine).not_to have_received(:tick)
  end

  %i[draft paused canceled sent failed].each do |status|
    it "does not tick an already #{status} campaign" do
      campaign.update!(status: status)
      described_class.perform_now(campaign.id)
      expect(campaign.reload.status).to eq(status.to_s)
      expect(engine).not_to have_received(:tick)
    end
  end

  it 'waits for an outer transaction commit before constructing or invoking the engine' do
    EmailCampaign.transaction do
      described_class.perform_now(campaign.id)
      expect(campaign.reload).to be_sending
      expect(engine_transactions).to eq([])
      expect(EmailCampaigns::DirectInbox::DeliveryEngine).not_to have_received(:new)
    end
    expect(engine_transactions).to eq([0])
  end

  it 'does not invoke the engine after the surrounding promotion rolls back' do
    EmailCampaign.transaction do
      described_class.perform_now(campaign.id)
      raise ActiveRecord::Rollback
    end
    expect(campaign.reload).to be_scheduled
    expect(engine_transactions).to eq([])
    expect(EmailCampaigns::DirectInbox::DeliveryEngine).not_to have_received(:new)
  end
end
