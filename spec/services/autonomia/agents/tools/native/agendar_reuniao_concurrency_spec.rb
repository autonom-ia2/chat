require 'rails_helper'
require 'timeout'

# J6-A3 (#1196): dois clientes, em duas conversas, pedem à IA o mesmo horário ao mesmo tempo. Concorrência real, em
# duas conexões, como em `booker_concurrency_spec`: a primeira reserva para DEPOIS de conferir o horário dentro das
# travas e ANTES de gravar; a segunda só segue quando a primeira termina. Uma vence; a outra recebe novas opções e
# nada de reserva dupla.
RSpec.describe Autonomia::Agents::Tools::Native::AgendarReuniao, :relationships_committed_fixtures do
  self.use_transactional_tests = false

  # Sem transação, o que for gravado fica no banco: anotamos o último id de auditoria antes de criar qualquer coisa
  # e, no fim, apagamos tudo o que a conta criou e conferimos que não sobrou nada.
  let!(:audit_floor) { Audited::Audit.maximum(:id).to_i }
  let!(:account) { create(:account) }
  let!(:world) { build_booking_world(account: account) }
  let!(:inbox) { create(:inbox, account: account) }
  let!(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Agenda', agent_type: 'scheduler', status: :active, enabled: true,
                                     instruction: 'Atenda.', config: { 'booking_page_id' => world.profile.id })
  end
  let(:slot) { '2026-10-20T10:00:00-03:00' }
  let(:paused) { Queue.new }
  let(:release) { Queue.new }
  let(:workers) { [] }

  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true', 'CRM_CALENDAR_MEETINGS_ENABLED' => 'true') { example.run }
  end

  before do
    travel_to Time.utc(2026, 10, 12, 11, 0, 0)
    account.enable_features!('crm_booking_v2')
    allow(Crm::Cards::Broadcaster).to receive(:broadcast)
  end

  after do
    release << true
    workers.each { |worker| worker.join(5) || worker.kill.join }
    cleanup_account!
    expect_nothing_left!
  end

  def account_tables
    [Crm::BookingInvite, Crm::MeetingGuest, Crm::Meeting, Crm::FollowUp, Crm::Activity, Crm::CardConversation, Crm::Card,
     Crm::AgentBookingLink, Crm::AgentBookingProfile, Crm::PipelineStage, Crm::Pipeline, Message, Conversation,
     Autonomia::Agents::Agent]
  end

  def cleanup_account!
    account_tables.each { |model| model.where(account_id: account.id).delete_all }
    contact_ids = Contact.where(account_id: account.id).pluck(:id)
    ContactInbox.where(contact_id: contact_ids).delete_all
    Contact.where(id: contact_ids).delete_all
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

  def expect_nothing_left!
    leftovers = (account_tables + [Contact, Inbox]).to_h { |model| [model.name, model.where(account_id: account.id).count] }
                                                   .select { |_, count| count.positive? }
    expect(leftovers).to be_empty, "sobrou no banco: #{leftovers}"
    expect(Account.exists?(account.id)).to be(false)
    expect(Audited::Audit.where('id > ?', audit_floor).count).to be_zero
  end

  # Pausa a primeira reserva logo depois da conferência do horário DENTRO das travas (a só local).
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

  def conversation_for(name, phone)
    contact = account.contacts.create!(name: name, phone_number: phone)
    create(:conversation, account: account, inbox: inbox, contact: contact)
  end

  def book_in_thread(conversation, pause: false)
    outcome = Queue.new
    workers << Thread.new do
      Thread.current[:pause_after_check] = pause
      ActiveRecord::Base.connection_pool.with_connection do
        delivery = Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: nil, origin_message_id: conversation.id)
        outcome << described_class.new(agent: agent, params: { 'inicio' => slot }, delivery: delivery).call
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

  it 'deixa só uma de duas reservas da IA no mesmo horário; a outra recebe novas opções' do
    pause_inside_lock
    first = book_in_thread(conversation_for('Ana', '+5521988887777'), pause: true)
    Timeout.timeout(10) { paused.pop }
    second = book_in_thread(conversation_for('Bruno', '+5521977776666'))
    wait_for_advisory_waiter!
    release << true

    winner, loser = [first, second].map { |queue| Timeout.timeout(15) { queue.pop } }

    expect(winner).to include('Reunião marcada')
    expect(loser).to include('NÃO foi marcado')
    expect(loser.lines.select { |line| line.start_with?('- ') }).not_to be_empty
    expect(loser).not_to include(slot)
    expect(Crm::Meeting.where(account_id: account.id, status: :scheduled, starts_at: Time.iso8601(slot)).count).to eq(1)
    expect(Crm::Meeting.where(account_id: account.id).pluck(:source)).to eq(['ai'])
  end
end
