require 'rails_helper'
require 'timeout'

# Concorrência real do claim (#1192): duas execuções do cron ao mesmo tempo, em conexões separadas e sem transação de
# teste. A primeira toma o aviso e para DENTRO do envio; a segunda roda inteira nesse meio-tempo. O aviso sai uma vez.
RSpec.describe Crm::BookingV2::NoticeDispatchJob, :relationships_committed_fixtures do
  self.use_transactional_tests = false

  let!(:audit_floor) { Audited::Audit.maximum(:id).to_i }
  let!(:account) { create(:account) }
  let!(:world) { build_booking_world(account: account) }
  let(:paused) { Queue.new }
  let(:release) { Queue.new }
  let(:workers) { [] }

  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true', 'CRM_CALENDAR_MEETINGS_ENABLED' => 'true') { example.run }
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
    [Crm::MeetingNotice, Crm::MeetingGuest, Crm::Meeting, Crm::FollowUp, Crm::Activity, Crm::Card, Crm::AgentBookingLink,
     Crm::AgentBookingProfile, Crm::PipelineStage, Crm::Pipeline, Contact]
  end

  # Mesmo método do spec de concorrência do Booker: apaga pelos ids da conta tudo o que o teste gravou.
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

  it 'duas execuções simultâneas mandam o aviso uma vez só' do
    meeting = create_internal_meeting(world: world, starts_at: 3.days.from_now)
    notice = Crm::MeetingNotice.create!(meeting: meeting, account: account, kind: 'booked', due_at: 1.minute.ago)
    deliveries = Queue.new
    queue = paused
    gate = release
    allow_any_instance_of(Crm::BookingV2::Notices::Sender).to receive(:perform) do # rubocop:disable RSpec/AnyInstance
      deliveries << true
      queue << true
      gate.pop
    end

    workers << Thread.new { ActiveRecord::Base.connection_pool.with_connection { described_class.perform_now } }
    Timeout.timeout(10) { paused.pop }
    second = Thread.new { ActiveRecord::Base.connection_pool.with_connection { described_class.perform_now } }
    workers << second
    Timeout.timeout(10) { second.join }
    release << true
    workers.first.join(10)

    expect(deliveries.size).to eq(1)
    expect(notice.reload).to have_attributes(status: 'sending', attempts: 1)
  end
end
