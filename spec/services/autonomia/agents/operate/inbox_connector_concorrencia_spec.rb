require 'rails_helper'

# #1366 — duas saídas ao mesmo tempo, em caixas diferentes, do mesmo agente. Sem a trava do agente, cada transação
# relia os vínculos vendo o da outra (a remoção dela ainda não tinha commit) e nenhuma parava o agente: ele ficava
# atendendo sem caixa nenhuma. Com a trava (agente → caixa), a segunda espera a primeira e enxerga que não sobrou nada.
RSpec.describe Autonomia::Agents::Operate::InboxConnector, :relationships_committed_fixtures do
  self.use_transactional_tests = false

  let!(:account) { create(:account) }
  let!(:primeira) { create(:inbox, account: account) }
  let!(:segunda) { create(:inbox, account: account) }
  let!(:agente) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bia', agent_type: 'custom', status: :active, enabled: true)
  end
  let(:chegou) { Queue.new }

  before do
    [primeira, segunda].each do |caixa|
      described_class.new(agent: agente, inbox: caixa).perform(connect: true)
    end
    # Cada parada relê os vínculos e espera a outra saída também ter relido (ou 1 s, o que vier primeiro). Sem a trava
    # do agente as duas releem antes de qualquer commit e cada uma vê o vínculo da outra; com a trava, a segunda nem
    # chega a reler enquanto a primeira não termina.
    fila = chegou
    allow_any_instance_of(Autonomia::Agents::Agent).to receive(:tem_onde_trabalhar?) # rubocop:disable RSpec/AnyInstance
      .and_wrap_original do |original|
        resposta = original.call
        fila << true
        sleep 0.05 until fila.size >= 2 || (Thread.current[:espera] ||= Time.current) < 1.second.ago
        resposta
      end
  end

  after do
    Autonomia::Agents::Agent.where(account_id: account.id).find_each(&:destroy!)
    AgentBot.where(account_id: account.id).find_each(&:destroy!)
    account.inboxes.find_each(&:destroy!)
    account.destroy!
    Audited::Audit.where(associated: account).or(Audited::Audit.where(auditable: account)).delete_all
  end

  def desconectar_em_paralelo(*caixas)
    caixas.map do |caixa|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |conexao|
          conexao.execute("SET lock_timeout = '10s'")
          agente_da_thread = Autonomia::Agents::Agent.find(agente.id)
          described_class.new(agent: agente_da_thread, inbox: caixa).perform(connect: false)
        end
      end
    end.map(&:value)
  end

  # parada automática concorrente
  it 'termina parado quando as duas últimas caixas saem ao mesmo tempo' do
    resultados = desconectar_em_paralelo(primeira, segunda)

    expect(resultados).to all(be_success)
    expect(Autonomia::Agents::AgentInbox.kept.where(autonomia_agent_id: agente.id)).to be_empty
    expect(agente.reload).to have_attributes(status: 'paused', enabled: false)
    expect(agente.events.parado_sem_onde_trabalhar.count).to eq(1)
  end
end
