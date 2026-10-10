require 'rails_helper'
require 'timeout'

# Concorrência real (#1189): duas reservas pelo MESMO convite ao mesmo tempo, em horários diferentes. Sem transação
# externa, o convite é conferido sem trava antes do Booker (os dois passam) e de novo, travado, dentro da transação do
# Booker. A primeira para DEPOIS de conferir o horário e ANTES de gravar; a segunda espera a trava de agente e, quando
# entra, acha o convite já agendado e desfaz a própria reunião. Sem a segunda conferência, o convite teria duas reuniões.
RSpec.describe Crm::BookingV2::PublicBooking, :relationships_committed_fixtures do
  self.use_transactional_tests = false

  # Sem transação, o que for gravado fica no banco: anota a última auditoria antes de criar qualquer coisa (o let! vem
  # antes do da conta) e apaga, no fim, tudo o que o teste criou.
  let!(:audit_floor) { Audited::Audit.maximum(:id).to_i }
  let!(:account) { create(:account) }
  let!(:world) { build_booking_world(account: account) }
  let!(:invite) { create_booking_invite(world: world) }
  let(:paused) { Queue.new }
  let(:release) { Queue.new }
  let(:workers) { [] }

  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true', 'CRM_CALENDAR_MEETINGS_ENABLED' => 'true') { example.run }
  end

  before do
    travel_to Time.utc(2026, 10, 12, 11, 0, 0)
    account.enable_features('crm_booking_v2')
    account.save!
    allow(Crm::Cards::Broadcaster).to receive(:broadcast)
  end

  after do
    release << true
    workers.each { |worker| worker.join(5) || worker.kill.join }
    cleanup_account!
  end

  def account_tables
    [Crm::BookingInvite, Crm::MeetingGuest, Crm::Meeting, Crm::FollowUp, Crm::Activity, Crm::Card, Crm::AgentBookingLink,
     Crm::AgentBookingProfile, Crm::PipelineStage, Crm::Pipeline, Contact]
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

  # Pausa a thread marcada logo depois da conferência SÓ local do horário (dentro das travas do Booker).
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

  def run_in_thread(starts_at, request_id, pause: false)
    outcome = Queue.new
    page = Crm::BookingV2::PublicPage.find(world.profile.slug)
    params = { name: 'Marcos Lima', starts_at: starts_at, invite_code: invite.code, request_id: request_id }
    workers << Thread.new do
      Thread.current[:pause_after_check] = pause
      ActiveRecord::Base.connection_pool.with_connection do
        outcome << [:ok, described_class.new(page: page, params: params).perform.meeting.id]
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

  it 'deixa só uma de duas reservas simultâneas pelo mesmo convite' do
    pause_inside_lock
    first = run_in_thread('2026-10-20T10:00:00-03:00', 'tentativa-primeira-01', pause: true)
    Timeout.timeout(10) { paused.pop }
    second = run_in_thread('2026-10-20T11:00:00-03:00', 'tentativa-segunda-001')
    wait_for_advisory_waiter!
    release << true

    outcomes = [first, second].map { |queue| Timeout.timeout(15) { queue.pop } }

    expect(outcomes.first.first).to eq(:ok)
    expect(outcomes.last).to eq([:error, 'booking_failed'])
    meeting = Crm::Meeting.where(account_id: account.id).sole
    expect(meeting).to have_attributes(id: outcomes.first.last, starts_at: Time.iso8601('2026-10-20T10:00:00-03:00'))
    expect(invite.reload).to have_attributes(meeting_id: meeting.id, metadata: { 'request_id' => 'tentativa-primeira-01' })
    expect(Crm::MeetingGuest.where(account_id: account.id).pluck(:meeting_id).uniq).to eq([meeting.id])
  end
end
