require 'rails_helper'
require 'timeout'

# #1366 — corrida entre o PATCH que ativa o agente e a desconexão da última caixa dele. Sem a trava do agente no update,
# a validação do PATCH via o vínculo que a desconexão estava tirando, e a parada automática da desconexão via o agente
# ainda parado (o PATCH não tinha commit): ele terminava atendendo sem caixa. Com a trava, a desconexão espera o PATCH
# e para o agente que ele acabou de ligar.
RSpec.describe 'PATCH autonomia/agents ativando enquanto a última caixa sai', :relationships_committed_fixtures, type: :request do
  self.use_transactional_tests = false

  let!(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let!(:inbox) { create(:inbox, account: account) }
  let!(:agente) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Livia', agent_type: 'custom', status: :active, enabled: true)
  end
  let(:releu) { Queue.new }

  around do |example|
    with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { example.run }
  end

  before do
    Autonomia::Agents::Operate::InboxConnector.new(agent: agente, inbox: inbox).perform(connect: true)
    agente.update!(status: :paused) # parado, mas ainda na caixa: o PATCH pode ativá-lo
    # Na thread do PATCH, a validação relê os vínculos e avisa; depois espera até 1 s, para a desconexão tentar entrar.
    fila = releu
    allow_any_instance_of(Autonomia::Agents::Agent).to receive(:tem_onde_trabalhar?) # rubocop:disable RSpec/AnyInstance
      .and_wrap_original do |original|
        resposta = original.call
        if Thread.current[:pausar_na_validacao]
          Thread.current[:pausar_na_validacao] = false
          fila << true
          sleep 1
        end
        resposta
      end
  end

  after do
    Autonomia::Agents::Agent.where(account_id: account.id).find_each(&:destroy!)
    AgentBot.where(account_id: account.id).find_each(&:destroy!)
    account.inboxes.find_each(&:destroy!)
    account.account_users.destroy_all
    account.destroy!
    NotificationSetting.where(user_id: admin.id).delete_all
    AccessToken.where(owner: admin).delete_all
    admin.destroy!
    Audited::Audit.where(associated: account).or(Audited::Audit.where(auditable: account)).delete_all
  end

  def em_thread(&)
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do |conexao|
        conexao.execute("SET lock_timeout = '10s'")
        yield
      end
    end
  end

  it 'termina parado: a desconexão espera o PATCH e para o agente que ele ligou' do
    headers = admin.create_new_auth_token
    patch_thread = em_thread do
      Thread.current[:pausar_na_validacao] = true
      sessao = ActionDispatch::Integration::Session.new(Rails.application)
      sessao.patch("/api/v1/accounts/#{account.id}/autonomia/agents/#{agente.id}",
                   params: { agent: { status: 'active' } }, headers: headers, as: :json)
      sessao.response.status
    end
    Timeout.timeout(10) { releu.pop }
    desconexao = em_thread do
      Autonomia::Agents::Operate::InboxConnector.new(agent: Autonomia::Agents::Agent.find(agente.id), inbox: inbox)
                                                .perform(connect: false)
    end

    expect([patch_thread.value, desconexao.value.success?]).to eq([200, true])
    expect(Autonomia::Agents::AgentInbox.kept.where(autonomia_agent_id: agente.id)).to be_empty
    expect(agente.reload).to have_attributes(status: 'paused', enabled: false)
  end
end
