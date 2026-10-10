require 'rails_helper'
require 'timeout'

# Concorrência real (#1190): dois pedidos do mesmo link ao mesmo tempo (mesma pessoa, mesmo cliente). O primeiro para
# DEPOIS de tomar a trava e ANTES de procurar o convite ativo; o segundo só pode seguir quando o primeiro gravar, e então
# reaproveita o convite em vez de criar outro. Sem a trava os dois achariam nada e criariam dois links ativos.
RSpec.describe Crm::BookingV2::InviteCreator, :relationships_committed_fixtures do
  self.use_transactional_tests = false

  # Sem transação, o que for gravado fica no banco: anota a última auditoria antes de criar qualquer coisa (o let! vem
  # antes do da conta) e apaga, no fim, tudo o que o teste criou.
  let!(:audit_floor) { Audited::Audit.maximum(:id).to_i }
  let!(:account) { create(:account) }
  let!(:world) { build_booking_world(account: account) }
  let(:paused) { Queue.new }
  let(:release) { Queue.new }
  let(:workers) { [] }

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

  # Pausa a thread marcada logo antes de procurar os convites ativos: a trava já foi tomada.
  def pause_before_lookup
    queue = paused
    gate = release
    allow_any_instance_of(described_class).to receive(:pending_invites).and_wrap_original do |original, *args| # rubocop:disable RSpec/AnyInstance
      if Thread.current[:pause_before_lookup]
        Thread.current[:pause_before_lookup] = false
        queue << true
        gate.pop
      end
      original.call(*args)
    end
  end

  def run_in_thread(pause: false)
    outcome = Queue.new
    workers << Thread.new do
      Thread.current[:pause_before_lookup] = pause
      ActiveRecord::Base.connection_pool.with_connection do
        creator = described_class.new(account: account, user: world.host, client: { card: world.card })
        outcome << [creator.perform.id, creator.reused?]
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

  it 'cria UM convite ativo quando dois pedidos chegam ao mesmo tempo' do
    pause_before_lookup
    first = run_in_thread(pause: true)
    Timeout.timeout(10) { paused.pop }
    second = run_in_thread
    wait_for_advisory_waiter!
    release << true

    outcomes = [first, second].map { |queue| Timeout.timeout(15) { queue.pop } }

    expect(outcomes.map(&:first).uniq.size).to eq(1)
    expect(outcomes.map(&:last)).to eq([false, true])
    expect(Crm::BookingInvite.where(account_id: account.id, canceled_at: nil).count).to eq(1)
  end
end
