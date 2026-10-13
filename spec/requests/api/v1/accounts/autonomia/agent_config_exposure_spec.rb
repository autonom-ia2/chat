require 'rails_helper'

# D5 — o jbuilder do agente expõe uma ALLOWLIST do jsonb `config`: chaves internas
# (knowledge_refresh_token, builder_active_thread_id, system_key, topic_map bruto...)
# nunca podem sair pela API.
# #1454 — `handoff_strategy`/`handoff_target_id` saíram do agente: quem recebe a conversa é a Atribuição do
# CRM. Agentes antigos ainda os têm no jsonb (não são apagados), mas a API não os expõe nem os grava mais.
RSpec.describe 'Autonomia agent config exposure', type: :request do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:administrator) { create(:user, account: account, role: :administrator) }

  let!(:agent) do
    Autonomia::Agents::Agent.create!(
      account: account, name: 'Agente', agent_type: 'custom',
      config: {
        'handoff_strategy' => 'low_confidence',
        'handoff_target_id' => 42,
        'confidence_threshold' => 0.7,
        'with_knowledge' => true,
        'knowledge_confidence' => 0.9,
        'knowledge_summary' => 'resumo',
        'knowledge_refresh_token' => 'super-secret-refresh-token',
        'builder_active_thread_id' => 123,
        'topic_map' => [{ 'topic' => 'precos', 'confidence' => 0.4 }],
        'test_allowlist_phones' => ['+5511999999999']
      }
    )
  end

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true' do
      example.run
    end
  end

  describe 'GET /api/v1/accounts/:account_id/autonomia/agents/:id' do
    it 'exposes only the allowlisted config keys' do
      # Arrange / Act
      get "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}",
          headers: administrator.create_new_auth_token,
          as: :json

      # Assert
      expect(response).to have_http_status(:success)
      config = response.parsed_body['config']
      expect(config.keys).to match_array(
        %w[confidence_threshold with_knowledge knowledge_confidence knowledge_summary]
      )
    end

    it 'never leaks internal config values anywhere in the payload' do
      # Arrange / Act
      get "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}",
          headers: administrator.create_new_auth_token,
          as: :json

      # Assert
      expect(response.body).not_to include('super-secret-refresh-token')
      expect(response.body).not_to include('builder_active_thread_id')
      expect(response.body).not_to include('test_allowlist_phones')
    end
  end

  describe 'PATCH /api/v1/accounts/:account_id/autonomia/agents/:id' do
    it 'ignores the retired handoff keys and keeps what the old agent already had stored' do
      # Act
      patch "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}",
            params: { agent: { config: { handoff_strategy: 'always_ask', handoff_target_id: 7, confidence_threshold: 0.5 } } },
            headers: administrator.create_new_auth_token,
            as: :json

      # Assert
      expect(response).to have_http_status(:success)
      expect(response.parsed_body['config'].keys).not_to include('handoff_strategy', 'handoff_target_id')
      expect(agent.reload.config).to include('handoff_strategy' => 'low_confidence', 'handoff_target_id' => 42,
                                             'confidence_threshold' => 0.5)
    end
  end

  describe 'POST /api/v1/accounts/:account_id/autonomia/agents' do
    it 'does not store the retired handoff keys on a new agent' do
      # Act
      post "/api/v1/accounts/#{account.id}/autonomia/agents",
           params: { agent: { name: 'Novo', agent_type: 'custom',
                              config: { handoff_strategy: 'never', handoff_target_id: 7, confidence_threshold: 0.4 } } },
           headers: administrator.create_new_auth_token,
           as: :json

      # Assert
      expect(response).to have_http_status(:created)
      config = Autonomia::Agents::Agent.find(response.parsed_body['id']).config
      expect(config.keys).not_to include('handoff_strategy', 'handoff_target_id')
      expect(config).to include('confidence_threshold' => 0.4)
    end
  end
end
