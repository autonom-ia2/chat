require 'rails_helper'
require 'timeout'

# Concorrência real (#1195): quem sai da conta tem as reuniões passadas para o responsável da página, enquanto um
# cliente marca com esse responsável ou o admin passa outra reunião para ele, no MESMO horário. Uma das duas conexões
# para DEPOIS de conferir a agenda e ANTES de gravar; a outra só pode seguir quando a primeira terminar. Sem a trava
# de quem recebe (e a conferência), o responsável ficaria com duas reuniões no mesmo horário.
RSpec.describe Crm::BookingV2::OrphanReassigner, :relationships_committed_fixtures do
  self.use_transactional_tests = false

  # Sem transação, o que for gravado fica no banco: anotamos a última auditoria antes de criar qualquer coisa e
  # apagamos tudo o que o teste criou no fim, conferindo que as tabelas da conta ficaram vazias.
  let!(:audit_floor) { Audited::Audit.maximum(:id).to_i }
  let!(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator, name: 'Admin') }
  let!(:world) { build_booking_world(account: account) }
  let!(:seller) { create(:user, account: account, role: :agent, name: 'Vendedor') }
  let!(:third) { create(:user, account: account, role: :agent, name: 'Paula Reis') }
  let!(:people_ids) { [admin.id, world.host.id, seller.id, third.id] }
  let(:slot) { ActiveSupport::TimeZone['America/Sao_Paulo'].parse('2026-10-20 10:00') }
  let(:paused) { Queue.new }
  let(:release) { Queue.new }
  let(:workers) { [] }

  around { |example| with_modified_env('CRM_CALENDAR_MEETINGS_ENABLED' => 'true') { example.run } }

  before do
    travel_to Time.utc(2026, 10, 12, 11, 0, 0)
    account.enable_features('crm_booking_v2')
    account.save!
    allow(Crm::Cards::Broadcaster).to receive(:broadcast)
    pause_on_busy_check
  end

  after do
    release << true
    workers.each { |worker| worker.join(5) || worker.kill.join }
    cleanup_account!
    ensure_nothing_left!
  end

  def account_tables
    [Crm::BookingInvite, Crm::MeetingGuest, Crm::Meeting, Crm::FollowUp, Crm::Activity, Crm::Card, Crm::AgentBookingLink,
     Crm::AgentBookingProfile, Crm::AgentAvailability, Crm::PipelineStage, Crm::Pipeline, Contact]
  end

  # Falha o exemplo se algo que o teste gravou sobrou no banco.
  def ensure_nothing_left!
    leftovers = account_tables.sum { |model| model.where(account_id: account.id).count } +
                AccountUser.where(user_id: people_ids).count + User.where(id: people_ids).count + Account.where(id: account.id).count
    raise "sobrou dado do teste no banco: #{leftovers} linha(s)" unless leftovers.zero?
  end

  def cleanup_account!
    account_tables.each { |model| model.where(account_id: account.id).delete_all }
    AccountUser.where(user_id: people_ids).delete_all
    NotificationSetting.where(user_id: people_ids).delete_all
    AccessToken.where(owner_type: 'User', owner_id: people_ids).delete_all
    User.where(id: people_ids).find_each(&:destroy!)
    account.reload.destroy!
    Audited::Audit.where('id > ?', audit_floor).delete_all
  end

  # A thread marcada para depois de N conferências de agenda (`Slots.busy_intervals`), já dentro da trava: a saída e o
  # Reassigner conferem uma vez por reunião (dentro da trava); o Booker confere fora (1ª) e dentro (2ª) das travas.
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

  # Quem sai: só a linha da conta some (o callback que enfileira o job não interessa aqui), e a saída roda direto.
  def seller_leaves
    AccountUser.where(account_id: account.id, user_id: seller.id).delete_all
    -> { described_class.new(account_id: account.id, user_id: seller.id).perform && nil }
  end

  def book
    Crm::BookingV2::Booker.new(profile: world.profile, name: 'Cliente', phone: '+5521988887777',
                               starts_at: slot.iso8601, source: 'public_link').perform.meeting.id
  end

  def host_meetings_at_slot
    Crm::Meeting.where(account_id: account.id, created_by_id: world.host.id, status: :scheduled, starts_at: slot)
  end

  it 'a saída passa a reunião primeiro: a reserva do responsável espera e recusa o mesmo horário' do
    orphan = page_meeting(seller)
    leave = seller_leaves

    first = run_in_thread(pause_on: 1) { leave.call }
    Timeout.timeout(10) { paused.pop }
    second = run_in_thread { book }
    wait_for_advisory_waiter!
    release << true

    outcomes = results(first, second)

    expect(outcomes.first).to eq([:ok, nil])
    expect(outcomes.last).to eq([:error, 'slot_unavailable'])
    expect(host_meetings_at_slot.pluck(:id)).to eq([orphan.id])
  end

  it 'a reserva vem primeiro: a saída espera, vê o horário ocupado e deixa a reunião para o admin passar' do
    orphan = page_meeting(seller)
    leave = seller_leaves

    first = run_in_thread(pause_on: 2) { book }
    Timeout.timeout(10) { paused.pop }
    second = run_in_thread { leave.call }
    wait_for_advisory_waiter!
    release << true

    outcomes = results(first, second)

    expect(outcomes.first.first).to eq(:ok)
    expect(host_meetings_at_slot.pluck(:id)).to eq([outcomes.first.last])
    expect(orphan.reload.created_by_id).to eq(seller.id)
    expect(Crm::BookingV2::AttentionReport.new(account: account).orphaned(world.profile))
      .to eq([{ id: seller.id, name: 'Vendedor', upcoming_meetings_count: 1 }])
  end

  it 'a saída e o "Passar reuniões" do admin para a mesma pessoa no mesmo horário: só uma reunião chega' do
    orphan = page_meeting(seller)
    manual = page_meeting(third)
    leave = seller_leaves
    reassigner = Crm::BookingV2::Reassigner.new(account: account, from_user_id: third.id, to_user_id: world.host.id, actor: admin)

    first = run_in_thread(pause_on: 1) { leave.call }
    Timeout.timeout(10) { paused.pop }
    second = run_in_thread { reassigner.perform.as_json }
    wait_for_advisory_waiter!
    release << true

    outcomes = results(first, second)

    expect(outcomes.first).to eq([:ok, nil])
    expect(outcomes.last.first).to eq(:ok)
    expect(outcomes.last.last[:moved]).to eq(0)
    expect(outcomes.last.last[:conflicts].map { |row| row[:meeting_id] }).to eq([manual.id])
    expect(host_meetings_at_slot.pluck(:id)).to eq([orphan.id])
    expect(manual.reload.created_by_id).to eq(third.id)
  end
end
