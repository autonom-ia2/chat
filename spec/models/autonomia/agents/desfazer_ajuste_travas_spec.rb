require 'rails_helper'
require 'timeout'

# #1428 (tema 6, parte 3, revisão adversarial D) — A ORDEM DAS TRAVAS com duas conexões reais. A escrita do Construtor
# trava a conversa e depois o agente; a volta por Versões e o Desfazer seguem a mesma ordem. Na ordem inversa (agente,
# depois conversa) a volta e a escrita simultâneas terminavam em ActiveRecord::Deadlocked.
RSpec.describe Autonomia::Agents::DesfazerAjuste, :relationships_committed_fixtures do
  self.use_transactional_tests = false

  let!(:account) { conta_da_fase2 }
  let!(:user) { create(:user, account: account) }
  let(:workers) { [] }
  let(:liberar_construtor) { Queue.new }
  let(:agente) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Hubber', agent_type: 'support', mode: :guided,
                                     instruction: 'Instrução antiga.', tone: 'cordial')
  end

  after do
    liberar_construtor << true
    workers.each { |worker| worker.join(1) || worker.kill.join }
  ensure
    Autonomia::Agents::InstructionVersion.where(account_id: account.id).delete_all
    Autonomia::Agents::BuildThread.where(account_id: account.id).delete_all
    Autonomia::Agents::Agent.where(account_id: account.id).delete_all
    account.account_users.destroy_all
    account.destroy!
    NotificationSetting.where(user_id: user.id).delete_all
    AccessToken.where(owner: user).delete_all
    user.destroy!
    Audited::Audit.where(associated: account).or(Audited::Audit.where(auditable: account)).delete_all
  end

  def em_conexao_propria(pids, resultados)
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do |conexao|
        conexao.execute("SET lock_timeout = '5s'")
        pids << conexao.select_value('SELECT pg_backend_pid()')
        resultados << yield
      rescue StandardError => e
        resultados << e.class.name
      end
    end
  end

  def esperar_travada(pid)
    Timeout.timeout(5) do
      sleep 0.02 until ActiveRecord::Base.connection.select_value(
        "SELECT wait_event_type = 'Lock' FROM pg_stat_activity WHERE pid = #{pid.to_i}"
      )
    end
  end

  # A escrita do Construtor parada depois de travar a conversa e antes de travar o agente. A conversa guarda o ajuste
  # de um turno anterior (a volta apaga essa chave).
  def construtor_parado_no_meio(pids, resultados)
    agente.send(:gravar_versao!, 'base', nil)
    conversa = Autonomia::Agents::BuildThread.create!(account: account, agent: agente, created_by: user,
                                                      status: :processing, build_token: 'ajuste',
                                                      state: { 'ultimo_ajuste' => { 'versao_antes_id' => 1 } })
    do_construtor = Autonomia::Agents::Agent.find(agente.id)
    em_andamento = Queue.new
    liberar = liberar_construtor
    allow(do_construtor).to receive(:apply_builder_attributes!).and_wrap_original do |original, *args|
      em_andamento << true
      liberar.pop
      original.call(*args)
    end
    workers << em_conexao_propria(pids, resultados) do
      do_construtor.apply_builder_config!(conversa.build_token, { tone: 'do Construtor' })
    end
    pids.pop
    em_andamento.pop
  end

  it 'a volta por Versões e a escrita do Construtor simultâneas terminam sem Deadlocked' do
    pids = Queue.new
    resultados = Queue.new
    construtor_parado_no_meio(pids, resultados)
    da_volta = Autonomia::Agents::Agent.find(agente.id)

    workers << em_conexao_propria(pids, resultados) do
      da_volta.restore_instruction!(agente.instruction_versions.first, created_by: user)
    end
    esperar_travada(pids.pop)
    liberar_construtor << true
    workers.each(&:join)

    expect([resultados.pop, resultados.pop]).to contain_exactly(true, true)
    expect(Autonomia::Agents::BuildThread.where(account_id: account.id).pluck(:state).map(&:keys).flatten)
      .not_to include('ultimo_ajuste')
  end
end
