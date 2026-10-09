require 'rails_helper'
require 'timeout'

# Remarcar sob disputa (#1192, J5-A3): remarcar e uma reserva nova do mesmo responsável para o mesmo horário, em
# conexões separadas e sem transação de teste. Quem chega primeiro para DENTRO das travas, depois da conferência
# local; o outro espera a trava e, ao seguir, encontra o horário tomado.
RSpec.describe Crm::BookingV2::ManageMeeting, :relationships_committed_fixtures do
  self.use_transactional_tests = false

  let!(:audit_floor) { Audited::Audit.maximum(:id).to_i }
  let!(:account) { create(:account) }
  let!(:world) { build_booking_world(account: account) }
  let(:target) { '2026-10-21T11:00:00-03:00' }
  let(:paused) { Queue.new }
  let(:release) { Queue.new }
  let(:workers) { [] }

  before do
    travel_to Time.utc(2026, 10, 12, 14, 0, 0)
    allow(Crm::Cards::Broadcaster).to receive(:broadcast)
  end

  after do
    release << true
    workers.each { |worker| worker.join(5) || worker.kill.join }
    user_ids = account.account_users.pluck(:user_id)
    cleanup_account!
    expect_nothing_left!(user_ids)
  end

  # Sem transação de teste: depois da limpeza, nenhuma linha do teste pode ter sobrado.
  def expect_nothing_left!(user_ids)
    left = account_tables.to_h { |model| [model.name, model.where(account_id: account.id).count] }
    left['Account'] = Account.where(id: account.id).count
    left['User'] = User.where(id: user_ids).count
    raise "concurrency spec leaked rows: #{left}" unless left.values.all?(&:zero?)
  end

  def account_tables
    [Crm::MeetingNotice, Crm::BookingNoticeStop, Crm::BookingInvite, Crm::MeetingGuest, Crm::Meeting, Crm::FollowUp, Crm::Activity,
     Crm::Card, Crm::AgentBookingLink, Crm::AgentBookingProfile, Crm::PipelineStage, Crm::Pipeline, Contact]
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

  # Pausa na conferência SÓ local (a que roda dentro das travas), igual ao spec de concorrência do Booker.
  def pause_inside_lock
    queue = paused
    gate = release
    allow_any_instance_of(Crm::BookingV2::Slots).to receive(:perform).and_wrap_original do |original, *args| # rubocop:disable RSpec/AnyInstance
      result = original.call(*args)
      if Thread.current[:pause_after_check] && !original.receiver.send(:include_provider)
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
      rescue ArgumentError, Crm::BookingV2::ManageError => e
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

  def scheduled_invite
    meeting = create_internal_meeting(world: world, starts_at: Time.utc(2026, 10, 20, 13, 0, 0),
                                      metadata: { 'booking_profile_id' => world.profile.id })
    create_booking_invite(world: world, meeting: meeting, scheduled_at: Time.current, channel: 'public')
  end

  def reschedule(invite)
    described_class.new(invite).reschedule!(starts_at: target)
  end

  def book_new
    Crm::BookingV2::Booker.new(profile: world.profile, name: 'Outra Cliente', phone: '+5521977776666', starts_at: target,
                               source: 'public_link').perform
  end

  def taken_at_target
    Crm::Meeting.where(account_id: account.id, status: :scheduled, starts_at: Time.iso8601(target)).count
  end

  it 'remarcar primeiro: a reserva nova do mesmo horário espera e é recusada' do
    invite = scheduled_invite
    pause_inside_lock
    first = run_in_thread(pause: true) { reschedule(invite) }
    Timeout.timeout(10) { paused.pop }
    second = run_in_thread { book_new }
    wait_for_advisory_waiter!
    release << true

    outcomes = results(first, second)

    expect(outcomes.first.first).to eq(:ok)
    expect(outcomes.last).to eq([:error, 'slot_unavailable'])
    expect(taken_at_target).to eq(1)
    expect(invite.meeting.reload.starts_at).to eq(Time.iso8601(target))
  end

  it 'reserva primeiro: remarcar para o mesmo horário espera e é recusado, sem mexer na reunião' do
    invite = scheduled_invite
    pause_inside_lock
    first = run_in_thread(pause: true) { book_new }
    Timeout.timeout(10) { paused.pop }
    second = run_in_thread { reschedule(invite) }
    wait_for_advisory_waiter!
    release << true

    outcomes = results(first, second)

    expect(outcomes.first.first).to eq(:ok)
    expect(outcomes.last).to eq([:error, 'slot_unavailable'])
    expect(taken_at_target).to eq(1)
    expect(invite.meeting.reload.starts_at).to eq(Time.utc(2026, 10, 20, 13, 0, 0))
  end
end
