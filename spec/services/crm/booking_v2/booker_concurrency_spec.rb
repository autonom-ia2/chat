require 'rails_helper'
require 'timeout'

# Concorrência real (#1188): duas conexões reservando o mesmo horário do mesmo responsável. A primeira para DEPOIS de
# conferir o horário e ANTES de gravar; a segunda só pode seguir quando a primeira terminar. Sem o lock as duas
# passariam pela conferência e marcariam o mesmo horário.
RSpec.describe Crm::BookingV2::Booker, :relationships_committed_fixtures do
  self.use_transactional_tests = false

  # Sem transação, o que for gravado fica no banco. As auditorias (gem audited) de conta, usuário e caixa também:
  # anotamos o último id antes de criar qualquer coisa (o let! vem antes do da conta) e apagamos o que veio depois, para não vazar para outros testes
  # do mesmo processo (ex.: specs de auditoria do enterprise contam linhas).
  let!(:audit_floor) { Audited::Audit.maximum(:id).to_i }
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

  # Apaga tudo o que o teste gravou, pelos ids anotados: dados do CRM da conta, caixas e seus horários, pessoas e o que
  # o Chatwoot cria junto com elas (vínculo com a conta, token, notificações), a conta e as auditorias.
  def cleanup_account!
    account_tables.each { |model| model.where(account_id: account.id).delete_all }
    user_ids = account.account_users.pluck(:user_id)
    cleanup_inboxes!
    cleanup_people!(user_ids)
    account.reload.destroy!
    Audited::Audit.where('id > ?', audit_floor).delete_all
  end

  def cleanup_inboxes!
    inbox_ids = Inbox.where(account_id: account.id).pluck(:id)
    Inbox.where(id: inbox_ids).find_each(&:destroy!)
    WorkingHour.where(inbox_id: inbox_ids).or(WorkingHour.where(account_id: account.id)).delete_all
  end

  def cleanup_people!(user_ids)
    AccountUser.where(user_id: user_ids).delete_all
    NotificationSetting.where(user_id: user_ids).delete_all
    AccessToken.where(owner_type: 'User', owner_id: user_ids).delete_all
    User.where(id: user_ids).find_each(&:destroy!)
  end

  # A thread marcada para "pausar" para logo depois da conferência do horário, ainda dentro do lock. O Booker confere
  # duas vezes: com o provedor ANTES das travas e só local DENTRO delas (`include_provider: false`); pausa nesta.
  def pause_after(klass, inside_lock: ->(_instance) { true })
    queue = paused
    gate = release
    allow_any_instance_of(klass).to receive(:perform).and_wrap_original do |original, *args| # rubocop:disable RSpec/AnyInstance
      result = original.call(*args)
      if Thread.current[:pause_after_check] && inside_lock.call(original.receiver)
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

  def v2_inside_lock
    ->(slots) { !slots.send(:include_provider) }
  end

  def book_v2(phone, profile: world.profile)
    described_class.new(profile: profile, name: 'Cliente', phone: phone, starts_at: slot, source: 'public_link').perform
  end

  def results(*queues)
    queues.map { |queue| Timeout.timeout(15) { queue.pop } }
  end

  it 'deixa só uma de duas reservas v2 simultâneas do mesmo horário' do
    pause_after(Crm::BookingV2::Slots, inside_lock: v2_inside_lock)
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

  # Responsáveis diferentes não disputam a trava de agente: só a de telefone impede dois contatos para o mesmo número.
  it 'cria UM contato quando o mesmo telefone novo reserva com dois responsáveis ao mesmo tempo' do
    other_host = create(:user, account: account, role: :agent, name: 'Outro Responsável')
    other_page = create_booking_profile(account: account, host: other_host, pipeline: world.pipeline, stage: world.stage)
    pause_after(Crm::BookingV2::Slots, inside_lock: v2_inside_lock)
    first = run_in_thread(pause: true) { book_v2('+5521966665555') }
    Timeout.timeout(10) { paused.pop }
    second = run_in_thread { book_v2('+5521966665555', profile: other_page) }
    wait_for_advisory_waiter!
    release << true

    outcomes = results(first, second)

    expect(outcomes.map(&:first)).to eq(%i[ok ok])
    expect(Contact.where(account_id: account.id, phone_number: '+5521966665555').count).to eq(1)
    expect(Crm::Meeting.where(account_id: account.id, status: :scheduled).pluck(:created_by_id)).to contain_exactly(world.host.id, other_host.id)
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
      pause_after(Crm::BookingV2::Slots, inside_lock: v2_inside_lock)
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
