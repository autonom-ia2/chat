require 'rails_helper'
require 'timeout'

# Concorrência real (#1188): duas conexões reservando o mesmo horário do mesmo responsável. A primeira para DEPOIS de
# conferir o horário e ANTES de gravar; a segunda só pode seguir quando a primeira terminar. Sem o lock as duas
# passariam pela conferência e marcariam o mesmo horário.
RSpec.describe Crm::BookingV2::Booker, :relationships_committed_fixtures do
  self.use_transactional_tests = false

  let!(:account) { create(:account) }
  let!(:world) { build_booking_world(account: account) }
  let(:slot) { '2026-10-20T10:00:00-03:00' }
  let(:paused) { Queue.new }
  let(:release) { Queue.new }
  let(:workers) { [] }

  before do
    travel_to Time.utc(2026, 10, 12, 11, 0, 0)
    allow(Crm::Cards::Broadcaster).to receive(:broadcast)
  end

  after do
    release << true
    workers.each { |worker| worker.join(5) || worker.kill.join }
    cleanup_account!
  end

  def account_tables
    [Crm::MeetingGuest, Crm::Meeting, Crm::FollowUp, Crm::Activity, Crm::Card, Crm::AgentBookingLink,
     Crm::AgentBookingProfile, Crm::PipelineStage, Crm::Pipeline, Contact]
  end

  def cleanup_account!
    account_tables.each { |model| model.where(account_id: account.id).delete_all }
    users = User.where(id: account.account_users.select(:user_id)).to_a
    Inbox.where(account_id: account.id).find_each(&:destroy!)
    account.account_users.delete_all
    users.each(&:destroy!)
    account.reload.destroy!
  end

  # A thread marcada para "pausar" para logo depois da conferência do horário, ainda dentro do lock.
  def pause_after(klass)
    queue = paused
    gate = release
    allow_any_instance_of(klass).to receive(:perform).and_wrap_original do |original, *args| # rubocop:disable RSpec/AnyInstance
      result = original.call(*args)
      if Thread.current[:pause_after_check]
        Thread.current[:pause_after_check] = false
        queue << true
        gate.pop
      end
      result
    end
  end

  def run_in_thread(pause: false)
    outcome = Queue.new
    workers << Thread.new do
      Thread.current[:pause_after_check] = pause
      ActiveRecord::Base.connection_pool.with_connection do
        outcome << [:ok, yield]
      rescue ArgumentError => e
        outcome << [:error, e.message]
      end
    end
    outcome
  end

  def wait_for_advisory_waiter!
    Timeout.timeout(10) do
      sleep 0.05 until ActiveRecord::Base.connection.select_value(
        "SELECT count(*) FROM pg_locks WHERE locktype = 'advisory' AND NOT granted"
      ).to_i.positive?
    end
  end

  def book_v2(phone)
    described_class.new(profile: world.profile, host: world.host, name: 'Cliente', phone: phone, starts_at: slot, source: 'public_link').perform
  end

  def results(*queues)
    queues.map { |queue| Timeout.timeout(15) { queue.pop } }
  end

  it 'deixa só uma de duas reservas v2 simultâneas do mesmo horário' do
    pause_after(Crm::BookingV2::Slots)
    first = run_in_thread(pause: true) { book_v2('+5521988887777') }
    Timeout.timeout(10) { paused.pop }
    second = run_in_thread { book_v2('+5521977776666') }
    wait_for_advisory_waiter!
    release << true

    outcomes = results(first, second)

    expect(outcomes.first.first).to eq(:ok)
    expect(outcomes.last).to eq([:error, 'slot_unavailable'])
    expect(Crm::Meeting.where(account_id: account.id, status: :scheduled).count).to eq(1)
  end

  context 'with a página antiga (v1) do mesmo responsável' do
    let!(:inbox) { create(:channel_email, account: account, provider: 'google', calendar_enabled: true).inbox }
    let!(:legacy_profile) do
      create_booking_profile(account: account, host: world.host, pipeline: world.pipeline, stage: world.stage,
                             page_version: Crm::AgentBookingProfile::LEGACY_PAGE, inbox: inbox, locations: [])
    end

    def book_v1
      Crm::Calendar::PublicBookingService.new(profile: legacy_profile, name: 'Ana', email: 'ana@example.com', starts_at: slot)
                                         .confirm_booking!
    end

    it 'v2 espera a v1 terminar e recusa o horário' do
      pause_after(Crm::Calendar::PublicAvailableSlots)
      first = run_in_thread(pause: true) { book_v1 }
      Timeout.timeout(10) { paused.pop }
      second = run_in_thread { book_v2('+5521988887777') }
      wait_for_advisory_waiter!
      release << true

      outcomes = results(first, second)

      expect(outcomes.first.first).to eq(:ok)
      expect(outcomes.last).to eq([:error, 'slot_unavailable'])
      expect(Crm::Meeting.where(account_id: account.id, status: :scheduled).pluck(:provider)).to eq(['google'])
    end

    it 'v1 espera a v2 terminar e recusa o horário' do
      pause_after(Crm::BookingV2::Slots)
      first = run_in_thread(pause: true) { book_v2('+5521988887777') }
      Timeout.timeout(10) { paused.pop }
      second = run_in_thread { book_v1 }
      wait_for_advisory_waiter!
      release << true

      outcomes = results(first, second)

      expect(outcomes.first.first).to eq(:ok)
      expect(outcomes.last).to eq([:error, 'slot_unavailable'])
      expect(Crm::Meeting.where(account_id: account.id, status: :scheduled).pluck(:provider)).to eq(['internal'])
    end
  end
end
