require 'rails_helper'
require 'timeout'

# O reaper e a mensagem do dono precisam disputar a mesma linha do agente antes de tocar a thread.
# Este arquivo desliga a transação global do RSpec de propósito: a prova usa duas conexões reais do
# Postgres e coordena a interlevação por filas, sem sleeps ou banco/serviço compartilhado.
RSpec.describe Autonomia::Agents::ReapStaleDraftsJob, type: :job do
  self.use_transactional_tests = false

  let!(:account) { create(:account) }
  let!(:agent) do
    Autonomia::Agents::Agent.create!(
      account: account, name: 'Rascunho concorrente', agent_type: 'custom',
      mode: :guided, status: :draft, enabled: false, actuation: :external
    )
  end
  let!(:thread_record) do
    Autonomia::Agents::BuildThread.create!(
      account: account, agent: agent,
      messages: [{ 'role' => 'assistant', 'content' => 'Qual é o nome?' }]
    )
  end
  let(:workers) { [] }

  before do
    stale_at = 3.days.ago
    agent.update_columns(updated_at: stale_at) # rubocop:disable Rails/SkipsModelValidations
    thread_record.update_columns(updated_at: stale_at) # rubocop:disable Rails/SkipsModelValidations
  end

  after do
    workers.each { |worker| worker.join(5) || worker.kill.join }
    Audited.audit_class.where(auditable_type: agent.class.name, auditable_id: agent.id).delete_all
    Autonomia::Agents::BuildThread.where(id: thread_record.id).delete_all
    Autonomia::Agents::Agent.where(id: agent.id).delete_all
    account.destroy!
  rescue ActiveRecord::RecordNotFound
    # A failed setup must not prevent the worker cleanup above from running.
  end

  it 'keeps the draft when the user append commits before the reaper final check' do
    append_locked = Queue.new
    release_append = Queue.new
    reaper_attempted_lock = Queue.new
    append_lock_acquired = false

    # The append worker reports only after it has acquired the agent row. With the current
    # implementation it never reports: append_message! updates the thread directly, which is the RED
    # proof for RUN-01. Once the lock is acquired, the reaper is allowed to contend for the same row.
    # rubocop:disable RSpec/AnyInstance
    allow_any_instance_of(Autonomia::Agents::Agent).to receive(:with_lock).and_wrap_original do |original, *args, &block|
      if Thread.current[:autonomia_append_worker]
        original.call(*args) do |locked_agent|
          append_locked << :locked
          release_append.pop
          block.call(locked_agent)
        end
      else
        reaper_attempted_lock << :attempted if Thread.current[:autonomia_reaper_worker]
        original.call(*args, &block)
      end
    end
    # rubocop:enable RSpec/AnyInstance

    append_worker = Thread.new do
      Thread.current[:autonomia_append_worker] = true
      ActiveRecord::Base.connection_pool.with_connection do
        Autonomia::Agents::BuildThread
          .find(thread_record.id)
          .append_message!('user', 'Quero continuar.')
      end
    end
    workers << append_worker

    begin
      append_lock_acquired = Timeout.timeout(5) { append_locked.pop } == :locked

      reaper_worker = Thread.new do
        Thread.current[:autonomia_reaper_worker] = true
        ActiveRecord::Base.connection_pool.with_connection { described_class.new.perform }
      end
      workers << reaper_worker
      Timeout.timeout(5) { reaper_attempted_lock.pop }

      # Release the owner append first. The reaper can only run its final stale check after this
      # transaction commits, so the user response must protect the agent from logical deletion.
      release_append << :release
      expect(append_worker.join(5)).to eq(append_worker)
      expect(reaper_worker.join(5)).to eq(reaper_worker)
    ensure
      release_append << :release if append_lock_acquired
      workers.each { |worker| worker.join(5) || worker.kill.join }
    end

    expect(agent.reload).not_to be_deleted
    expect(Array(thread_record.reload.messages)).to include(
      hash_including('role' => 'user', 'content' => 'Quero continuar.')
    )
  end

  it 'uses Agent before Thread for builder writes so the append cannot deadlock it' do
    append_agent_lock_started = Queue.new
    release_append = Queue.new
    builder_agent_attempted = Queue.new
    append_agent_lock_started_seen = false

    # This is the inverse interleaving found in the runtime trace: the append owns Agent and is
    # paused immediately before its atomic thread UPDATE; the old Builder owns Thread and waits for
    # Agent. The fixed order makes the Builder wait before taking Thread, so releasing the append
    # always lets both transactions finish. The test deliberately does not require BuildThread#with_lock:
    # the production append may use the atomic UPDATE as its thread lock.
    # rubocop:disable RSpec/AnyInstance
    allow_any_instance_of(Autonomia::Agents::Agent).to receive(:with_lock).and_wrap_original do |original, *args, &block|
      if Thread.current[:autonomia_append_worker]
        original.call(*args) do |locked_agent|
          append_agent_lock_started << :started
          release_append.pop
          block.call(locked_agent)
        end
      elsif Thread.current[:autonomia_builder_worker]
        builder_agent_attempted << :attempted
        original.call(*args, &block)
      else
        original.call(*args, &block)
      end
    end
    # rubocop:enable RSpec/AnyInstance

    # Claim the build before either worker starts. Calling begin_build! while the append owns a lock
    # would make the fixture block before the intended interleaving is even established.
    build_token = thread_record.begin_build!

    append_worker = Thread.new do
      Thread.current[:autonomia_append_worker] = true
      ActiveRecord::Base.connection_pool.with_connection do
        Autonomia::Agents::BuildThread
          .find(thread_record.id)
          .append_message!('user', 'Resposta concorrente.')
      end
    end
    workers << append_worker

    begin
      append_agent_lock_started_seen = Timeout.timeout(5) { append_agent_lock_started.pop } == :started

      builder_worker = Thread.new do
        Thread.current[:autonomia_builder_worker] = true
        ActiveRecord::Base.connection_pool.with_connection do
          Autonomia::Agents::Agent.find(agent.id).apply_builder_config!(
            build_token, { config: { 'guardrails' => 'safe' } }
          )
        end
      end
      workers << builder_worker
      Timeout.timeout(5) { builder_agent_attempted.pop }

      release_append << :release
      expect(append_worker.join(5)).to eq(append_worker)
      expect(builder_worker.join(5)).to eq(builder_worker)
    ensure
      release_append << :release if append_agent_lock_started_seen
      workers.each { |worker| worker.join(5) || worker.kill.join }
    end
  end

  it 'keeps the legacy unlinked interview thread appendable' do
    unlinked_thread = Autonomia::Agents::BuildThread.create!(account: account)

    expect { unlinked_thread.append_message!('user', 'Ainda estou escolhendo.') }.not_to raise_error
    expect(unlinked_thread.reload.messages).to include(
      hash_including('role' => 'user', 'content' => 'Ainda estou escolhendo.')
    )
  ensure
    Autonomia::Agents::BuildThread.where(id: unlinked_thread&.id).delete_all
  end
end
