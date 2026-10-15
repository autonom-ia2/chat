require 'rails_helper'

# #1648 — com a chave da conta `autonomia_agente_ia_por_caixa` DESLIGADA (o padrão), a conta fica como a main: sem a
# leitura e a troca da aba "Agente de IA", o set_agent_bot do Chatwoot sem a recusa e a lista de robôs com os espelhos.
RSpec.describe 'Agente de IA por caixa desligada', type: :request do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:headers) { admin.create_new_auth_token }
  let(:externo) { create(:agent_bot, account: account, name: 'Automação', outgoing_url: 'https://automacao.example.com/hook') }
  let(:agente) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Sofia', agent_type: 'custom', status: :active, enabled: true)
  end
  let!(:vinculo) { Autonomia::Agents::Operate::InboxConnector.new(agent: agente, inbox: inbox).perform(connect: true).agent_inbox }

  around do |example|
    with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { example.run }
  end

  it 'starts off on a new account' do
    expect(Autonomia::Agents::AgenteIaPorCaixa.ligada?(account)).to be(false)
  end

  it 'answers 404 to the AI agent tab, read and swap' do
    url = "/api/v1/accounts/#{account.id}/autonomia/inboxes/#{inbox.id}/quem_atende"

    get url, headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
    put url, params: { agent_bot_id: externo.id }, headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
    expect(AgentBotInbox.where(inbox_id: inbox.id).pluck(:agent_bot_id)).to eq([vinculo.agent_bot_id])
  end

  it 'keeps the Chatwoot set_agent_bot: plugs the agent from another system over the mirror, as on main' do
    post "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/set_agent_bot",
         params: { agent_bot: externo.id }, headers: headers, as: :json

    expect(response).to have_http_status(:ok)
    expect(AgentBotInbox.where(inbox_id: inbox.id).pluck(:agent_bot_id)).to eq([externo.id])
  end

  it 'lists the mirrors of platform agents in agent_bots and opens them by id, as on main' do
    get "/api/v1/accounts/#{account.id}/agent_bots", headers: headers, as: :json
    expect(response.parsed_body.pluck('id')).to include(vinculo.agent_bot_id)

    get "/api/v1/accounts/#{account.id}/agent_bots/#{vinculo.agent_bot_id}", headers: headers, as: :json
    expect(response).to have_http_status(:ok)
  end

  it 'turns on and off by the account key' do
    Autonomia::Agents::AgenteIaPorCaixa.ligar!(account)
    expect(Autonomia::Agents::AgenteIaPorCaixa.ligada?(account.reload)).to be(true)

    Autonomia::Agents::AgenteIaPorCaixa.desligar!(account)
    expect(Autonomia::Agents::AgenteIaPorCaixa.ligada?(account.reload)).to be(false)
  end
end
