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
      expect(body['meta']).to include('metric' => 'handled', 'range' => '7d', 'count' => 1, 'has_more' => false)
      expect(body['payload'].size).to eq(1)
      expect(body['payload'].first['record_type']).to eq('conversation')
      expect(body['payload'].first['conversation']['display_id']).to eq(conversation.display_id)
    end

    it 'evaluates the heavy conversation scope only once (no separate count)' do
      conversation_queries = []
      subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |_name, _start, _finish, _id, payload|
        conversation_queries << payload[:sql] if payload[:sql].include?('FROM "conversations"')
      end

      get "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}/analytics/conversations",
          params: { range: '7d', metric: 'handled' }, headers: administrator.create_new_auth_token, as: :json

      ActiveSupport::Notifications.unsubscribe(subscriber)
      expect(response).to have_http_status(:success)
      expect(conversation_queries.size).to eq(1)
      expect(conversation_queries.first).to include('LIMIT')
    end

    it 'flags has_more when the result exceeds the drilldown limit' do
      stub_const('Api::V1::Accounts::Autonomia::Agents::AnalyticsController::DRILLDOWN_LIMIT', 1)
      other = create(:conversation, account: account, inbox: inbox)
      Autonomia::Agents::AgentEvent.create!(agent: agent, account: account, conversation_id: other.id, event_type: :replied)

      get "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}/analytics/conversations",
          params: { range: '7d', metric: 'handled' }, headers: administrator.create_new_auth_token, as: :json

      expect(response.parsed_body['meta']).to include('count' => 1, 'has_more' => true, 'limit' => 1)
      expect(response.parsed_body['payload'].size).to eq(1)
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
