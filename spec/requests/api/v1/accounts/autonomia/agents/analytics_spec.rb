require 'rails_helper'

# #284 — aba Desempenho: `outcomes` no payload e a lista de conversas por resultado.
RSpec.describe 'Autonomia agent analytics', type: :request do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Ana', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda.')
  end
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true' do
      example.run
    end
  end

  before do
    Autonomia::Agents::AgentEvent.create!(agent: agent, account: account, conversation_id: conversation.id, event_type: :replied)
  end

  describe 'GET .../analytics' do
    it 'includes the outcome counts' do
      get "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}/analytics",
          params: { range: '7d' }, headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['outcomes']).to eq(
        'handled' => 1, 'resolved_without_human' => 0, 'handed_off' => 0, 'reopened' => 0, 'wrong_replies' => 0
      )
    end
  end

  describe 'GET .../analytics/conversations' do
    it 'lists the conversations behind a metric with the drilldown record shape' do
      get "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}/analytics/conversations",
          params: { range: '7d', metric: 'handled' }, headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['meta']).to include('metric' => 'handled', 'range' => '7d', 'total_count' => 1)
      expect(body['payload'].size).to eq(1)
      expect(body['payload'].first['record_type']).to eq('conversation')
      expect(body['payload'].first['conversation']['display_id']).to eq(conversation.display_id)
    end

    it 'rejects an unknown metric' do
      get "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}/analytics/conversations",
          params: { range: '7d', metric: 'bogus' }, headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'is admin-only like the rest of the agents area' do
      agent_user = create(:user, account: account, role: :agent)

      get "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}/analytics/conversations",
          params: { range: '7d', metric: 'handled' }, headers: agent_user.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
