require 'rails_helper'

# Caixas no CRM → Quem cuida do quê? (#1447): a função com crm_admin configura a caixa, mas pôr ou tirar agente de IA é
# mexer no agente e pede também autonomia_manage.
RSpec.describe 'CRM Caixas no CRM API — agentes de IA por função', type: :request do
  around do |example|
    with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run }
  end

  let!(:account_and_admin) { create_account_and_user }
  let(:account) { account_and_admin.first }
  let(:admin) { account_and_admin.last }
  let(:inbox) { create_crm_inbox(account: account, name: 'WhatsApp Comercial') }
  let(:vendas) { create_crm_pipeline(account: account, user: admin, name: 'Vendas').first }
  let(:url) { "/api/v1/accounts/#{account.id}/crm/caixas/#{inbox.id}" }
  let(:marta) { Autonomia::Agents::Agent.create!(account: account, name: 'Marta', agent_type: 'custom', status: :active, enabled: true) }

  before do
    account.enable_features!('crm_configurar_caixas')
    allow(Autonomia::Agents::Config).to receive(:enabled?).and_call_original
    allow(Autonomia::Agents::Config).to receive(:enabled?).with(account).and_return(true)
    Autonomia::Agents::Fase2.ligar!(account)
    porta = Autonomia::Agents::Agent.create!(account: account, name: 'Clara', agent_type: 'custom', status: :active, enabled: true)
    Autonomia::Agents::Operate::InboxConnector.new(agent: porta, inbox: inbox).perform(connect: true)
    marta
  end

  def usuario_com(permissions)
    user, account_user = create_crm_agent(account: account, name: 'Com função')
    account_user.update!(custom_role: CustomRole.create!(account: account, name: "Função #{SecureRandom.hex(4)}", permissions: permissions))
    user
  end

  def salvar(user)
    put url, params: { caixa: { pipeline_ids: [vendas.id], modo: 'off', people: [], ai_agents: [{ id: marta.id, pipeline_ids: [vendas.id] }] } },
             headers: auth_headers(user), as: :json
  end

  it 'crm_admin sem autonomia_manage vê os agentes sem poder mudar e não grava' do
    user = usuario_com(['crm_admin'])

    get url, headers: auth_headers(user)
    expect(response.parsed_body.dig('payload', 'caixa', 'ai_agents')).to include('pode_mudar' => false, 'disponiveis' => [])

    salvar(user)
    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body.dig('error', 'code')).to eq('crm.caixas.agentes_sem_permissao')
    expect(Crm::InboxAiAgent.count).to eq(0)
    expect(Autonomia::Agents::AgentInbox.kept.area.where(agent: marta)).to be_empty
  end

  it 'crm_admin com autonomia_manage, membro da caixa, põe o agente na caixa' do
    user = usuario_com(%w[crm_admin autonomia_manage])
    inbox.add_members([user.id])

    salvar(user)

    expect(response).to have_http_status(:ok)
    expect(Crm::InboxAiAgent.pluck(:pipeline_id, :autonomia_agent_id)).to eq([[vendas.id, marta.id]])
  end

  # Regra G (#1788): mexer no agente da caixa pede alcançar a caixa (membro ou inbox_manage).
  describe 'sem ser membro da caixa' do
    it 'com crm_admin e autonomia_manage não põe o agente, e a tela não oferece' do
      user = usuario_com(%w[crm_admin autonomia_manage])

      get url, headers: auth_headers(user)
      expect(response.parsed_body.dig('payload', 'caixa', 'ai_agents')).to include('pode_mudar' => false)

      salvar(user)
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body.dig('error', 'code')).to eq('crm.caixas.agentes_sem_permissao')
      expect(Autonomia::Agents::AgentInbox.kept.area.where(agent: marta)).to be_empty
    end

    it 'a lista de caixas também não oferece mexer no agente' do
      get "/api/v1/accounts/#{account.id}/crm/caixas", headers: auth_headers(usuario_com(%w[crm_admin autonomia_manage]))

      caixa = response.parsed_body.dig('payload', 'caixas').find { |item| item.dig('inbox', 'id') == inbox.id }
      expect(caixa['ai_agents']).to include('pode_mudar' => false, 'disponiveis' => [])
    end

    it 'com inbox_manage também põe o agente' do
      salvar(usuario_com(%w[crm_admin autonomia_manage inbox_manage]))

      expect(response).to have_http_status(:ok)
      expect(Crm::InboxAiAgent.pluck(:autonomia_agent_id)).to eq([marta.id])
    end

    it 'com crm_admin continua salvando os funis da caixa quando o pedido não mexe nos agentes' do
      user = usuario_com(['crm_admin'])

      put url, params: { caixa: { pipeline_ids: [vendas.id], modo: 'off', people: [] } }, headers: auth_headers(user), as: :json

      expect(response).to have_http_status(:ok)
    end
  end
end
