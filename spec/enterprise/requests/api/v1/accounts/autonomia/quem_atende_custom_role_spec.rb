require 'rails_helper'

# #1648 (revisão) — trocar quem atende primeiro pede inbox_manage e, quando mexe em agente da plataforma (o que sai ou o
# que entra), também autonomia_manage. inbox_manage é delegável por função; mexer em agente da plataforma não vem junto.
RSpec.describe 'Autonomia quem_atende with custom roles', type: :request do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true, 'autonomia_agente_ia_por_caixa' => true }) }
  let(:inbox) { create(:inbox, account: account) }
  let(:url) { "/api/v1/accounts/#{account.id}/autonomia/inboxes/#{inbox.id}/quem_atende" }
  let(:automacao) { create(:agent_bot, account: account, name: 'Automação', outgoing_url: 'https://automacao.example.com/hook') }
  let(:parceiro) { create(:agent_bot, account: account, name: 'Parceiro', outgoing_url: 'https://parceiro.example.com/hook') }
  let(:sofia) { Autonomia::Agents::Agent.create!(account: account, name: 'Sofia', agent_type: 'custom', status: :active, enabled: true) }

  around do |example|
    with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { example.run }
  end

  def custom_role_user(*permissions)
    user = create(:user, account: account, role: :agent)
    role = create(:custom_role, account: account, permissions: permissions)
    user.account_users.find_by(account: account).update!(custom_role: role)
    user
  end

  def trocar(user, **params)
    put url, params: params, headers: user.create_new_auth_token, as: :json
  end

  def robos_da_caixa
    AgentBotInbox.where(inbox_id: inbox.id).pluck(:agent_bot_id)
  end

  context 'with only inbox_manage' do
    let(:so_caixa) { custom_role_user('inbox_manage') }

    it 'swaps between agents from another system' do
      AgentBotInbox.create!(inbox: inbox, agent_bot: automacao, account: account)

      trocar(so_caixa, agent_bot_id: parceiro.id)

      expect(response).to have_http_status(:ok)
      expect(robos_da_caixa).to eq([parceiro.id])
    end

    it 'refuses to put a platform agent in, and nothing changes' do
      trocar(so_caixa, agent_id: sofia.id)

      expect(response).to have_http_status(:unauthorized)
      expect(Autonomia::Agents::AgentInbox.where(inbox_id: inbox.id)).to be_empty
    end

    it 'refuses to take the platform agent out, and nothing changes' do
      vinculo = Autonomia::Agents::Operate::InboxConnector.new(agent: sofia, inbox: inbox).perform(connect: true).agent_inbox

      trocar(so_caixa, agent_bot_id: automacao.id)

      expect(response).to have_http_status(:unauthorized)
      expect(robos_da_caixa).to eq([vinculo.agent_bot_id])
    end
  end

  it 'with inbox_manage and autonomia_manage, puts the platform agent in' do
    trocar(custom_role_user('inbox_manage', 'autonomia_manage'), agent_id: sofia.id)

    expect(response).to have_http_status(:ok)
    expect(Autonomia::Agents::AgentInbox.kept.porta.find_by(inbox_id: inbox.id).autonomia_agent_id).to eq(sofia.id)
  end
end
