require 'rails_helper'

# #647 — o cartão do agente lê `channels_count`; a API precisa devolver a contagem real de canais
# (vínculos agente ↔ inbox), na listagem e no detalhe.
RSpec.describe 'Autonomia agent channels_count', type: :request do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent_bot) { create(:agent_bot, account: account) }

  let!(:connected_agent) { create_agent('Conectado') }
  let!(:idle_agent) { create_agent('Sem canal') }

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true' do
      example.run
    end
  end

  before do
    2.times { link(connected_agent, create(:inbox, account: account)) }
  end

  def create_agent(name)
    Autonomia::Agents::Agent.create!(account: account, name: name, agent_type: 'support')
  end

  def link(agent, inbox)
    Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: agent_bot)
  end

  it 'returns the real channels_count for each agent in the list' do
    get "/api/v1/accounts/#{account.id}/autonomia/agents",
        headers: administrator.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    counts = response.parsed_body['payload'].to_h { |agent| [agent['id'], agent['channels_count']] }
    expect(counts).to eq(connected_agent.id => 2, idle_agent.id => 0)
  end

  it 'reads the channel links in a single query for the whole list (no N+1)' do
    link_queries = []
    counter = lambda do |_name, _start, _finish, _id, payload|
      link_queries << payload[:sql] if payload[:sql].include?('autonomia_agent_inboxes')
    end

    ActiveSupport::Notifications.subscribed(counter, 'sql.active_record') do
      get "/api/v1/accounts/#{account.id}/autonomia/agents",
          headers: administrator.create_new_auth_token, as: :json
    end

    expect(response).to have_http_status(:success)
    expect(link_queries.size).to eq(1)
  end

  it 'returns channels_count on the agent detail' do
    get "/api/v1/accounts/#{account.id}/autonomia/agents/#{connected_agent.id}",
        headers: administrator.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(response.parsed_body['channels_count']).to eq(2)
  end
end
