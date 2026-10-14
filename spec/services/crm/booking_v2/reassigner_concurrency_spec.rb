require 'rails_helper'
require 'timeout'

# Concorrência real (#1195, J8-A10): duas conexões disputando o horário da mesma pessoa nova. A primeira para DEPOIS
# de conferir a ocupação e ANTES de gravar; a segunda só pode seguir quando a primeira terminar. Sem a trava de
# agente as duas passariam pela conferência e a pessoa ficaria com duas reuniões no mesmo horário.
RSpec.describe Crm::BookingV2::Reassigner, :relationships_committed_fixtures do
  self.use_transactional_tests = false

  # Sem transação, o que for gravado fica no banco: anotamos a última auditoria antes de criar qualquer coisa e
  # apagamos tudo o que o teste criou no fim, conferindo que as tabelas da conta ficaram vazias.
  let!(:audit_floor) { Audited::Audit.maximum(:id).to_i }
  let!(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator, name: 'Admin') }
  let!(:world) { build_booking_world(account: account) }
  let!(:target) { create(:user, account: account, role: :agent, name: 'Rui Prado') }
  let!(:third) { create(:user, account: account, role: :agent, name: 'Paula Reis') }
  let(:slot) { ActiveSupport::TimeZone['America/Sao_Paulo'].parse('2026-10-20 10:00') }
  let(:paused) { Queue.new }
  let(:release) { Queue.new }
  let(:workers) { [] }

  before do
    travel_to Time.utc(2026, 10, 12, 11, 0, 0)
    allow(Crm::Cards::Broadcaster).to receive(:broadcast)
    pause_on_busy_check
  end

  after do
    release << true
    workers.each { |worker| worker.join(5) || worker.kill.join }
    cleanup_account!
    ensure_nothing_left!
  end

  # Falha o exemplo se algo que o teste gravou sobrou no banco.
  def ensure_nothing_left!
    leftovers = account_tables.sum { |model| model.where(account_id: account.id).count } +
                User.where(id: [world.host.id, target.id, third.id, admin.id]).count + Account.where(id: account.id).count
    raise "sobrou dado do teste no banco: #{leftovers} linha(s)" unless leftovers.zero?
  end

  def account_tables
    [Crm::MeetingGuest, Crm::Meeting, Crm::FollowUp, Crm::Activity, Crm::Card, Crm::AgentBookingLink,
     Crm::AgentBookingProfile, Crm::AgentAvailability, Crm::PipelineStage, Crm::Pipeline, Contact]
  end

  def cleanup_account!
    account_tables.each { |model| model.where(account_id: account.id).delete_all }
    user_ids = account.account_users.pluck(:user_id)
    AccountUser.where(user_id: user_ids).delete_all
    NotificationSetting.where(user_id: user_ids).delete_all
    AccessToken.where(owner_type: 'User', owner_id: user_ids).delete_all
    User.where(id: user_ids).find_each(&:destroy!)
    account.reload.destroy!
    Audited::Audit.where('id > ?', audit_floor).delete_all
  end

  # A thread marcada para depois de N conferências de ocupação (`Slots.busy_intervals`), já dentro da trava: o
  # Reassigner confere uma vez por reunião (dentro da trava); o Booker confere fora (1ª) e dentro (2ª) das travas.
  def pause_on_busy_check
    queue = paused
    gate = release
    allow(Crm::BookingV2::Slots).to receive(:busy_intervals).and_wrap_original do |original, **kwargs|
      result = original.call(**kwargs)
      countdown = Thread.current[:pause_on_check]
      if countdown
        Thread.current[:pause_on_check] = countdown - 1
        if countdown == 1
          queue << true
          gate.pop
        end
      end
      result
    end
  end

  def run_in_thread(pause_on: nil)
    outcome = Queue.new
    workers << Thread.new do
      Thread.current[:pause_on_check] = pause_on
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

  def results(*queues)
    queues.map { |queue| Timeout.timeout(15) { queue.pop } }
  end

  def page_meeting(host)
    create_internal_meeting(world: world, starts_at: slot, created_by: host, metadata: { 'booking_profile_id' => world.profile.id })
  end

  def reassign(from)
    described_class.new(account: account, from_user_id: from.id, to_user_id: target.id, actor: admin).perform.as_json
  end

  def target_meetings_at_slot
    Crm::Meeting.where(account_id: account.id, created_by_id: target.id, status: :scheduled, starts_at: slot)
  end

  it 'duas passagens simultâneas para a mesma pessoa no mesmo horário: só uma reunião chega' do
    first_meeting = page_meeting(world.host)
    second_meeting = page_meeting(third)

    first = run_in_thread(pause_on: 1) { reassign(world.host) }
    Timeout.timeout(10) { paused.pop }
    second = run_in_thread { reassign(third) }
    wait_for_advisory_waiter!
    release << true

    outcomes = results(first, second)

    expect(outcomes.first).to eq([:ok, { moved: 1, conflicts: [] }])
    expect(outcomes.last.first).to eq(:ok)
    expect(outcomes.last.last[:moved]).to eq(0)
    expect(outcomes.last.last[:conflicts].map { |row| row[:meeting_id] }).to eq([second_meeting.id])
    expect(target_meetings_at_slot.pluck(:id)).to eq([first_meeting.id])
    expect(second_meeting.reload.created_by_id).to eq(third.id)
  end

  context 'with uma reserva pela página da pessoa nova no mesmo horário' do
    let!(:target_page) { create_booking_profile(account: account, host: target, pipeline: world.pipeline, stage: world.stage) }

    def book
      Crm::BookingV2::Booker.new(profile: target_page, name: 'Cliente', phone: '+5521988887777',
                                 starts_at: slot.iso8601, source: 'public_link').perform.meeting.id
    end

    it 'a reserva espera a passagem terminar e recusa o horário' do
      moving = page_meeting(world.host)

      first = run_in_thread(pause_on: 1) { reassign(world.host) }
      Timeout.timeout(10) { paused.pop }
      second = run_in_thread { book }
      wait_for_advisory_waiter!
      release << true

      outcomes = results(first, second)

      expect(outcomes.first).to eq([:ok, { moved: 1, conflicts: [] }])
      expect(outcomes.last).to eq([:error, 'slot_unavailable'])
      expect(target_meetings_at_slot.pluck(:id)).to eq([moving.id])
    end

    it 'a passagem espera a reserva terminar e devolve o horário como conflito' do
      moving = page_meeting(world.host)

      first = run_in_thread(pause_on: 2) { book }
      Timeout.timeout(10) { paused.pop }
      second = run_in_thread { reassign(world.host) }
      wait_for_advisory_waiter!
      release << true

      outcomes = results(first, second)

      expect(outcomes.first.first).to eq(:ok)
      booked_id = outcomes.first.last
      expect(outcomes.last.first).to eq(:ok)
      expect(outcomes.last.last[:moved]).to eq(0)
      expect(outcomes.last.last[:conflicts].map { |row| row[:meeting_id] }).to eq([moving.id])
      expect(target_meetings_at_slot.pluck(:id)).to eq([booked_id])
      expect(moving.reload.created_by_id).to eq(world.host.id)
    end
  end
end
