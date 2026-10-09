require 'rails_helper'

# D5 — o jbuilder do agente expõe uma ALLOWLIST do jsonb `config`: chaves internas
# (knowledge_refresh_token, builder_active_thread_id, system_key, topic_map bruto...)
# nunca podem sair pela API.
RSpec.describe 'Autonomia agent config exposure', type: :request do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:administrator) { create(:user, account: account, role: :administrator) }

  let!(:agent) do
    Autonomia::Agents::Agent.create!(
      account: account, name: 'Agente', agent_type: 'custom',
      config: {
        'handoff_strategy' => 'low_confidence',
        'handoff_target_type' => 'team',
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

  let(:quote_agent) do
    enable_test_encryption!
    Autonomia::Insurance::QuoteAgent::Builder.new(
      account: account, nome_agente: 'Lia', nome_corretora: 'Sena'
    ).call
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
        %w[handoff_strategy handoff_target_type handoff_target_id confidence_threshold with_knowledge knowledge_confidence knowledge_summary]
      )
      expect(config['handoff_target_type']).to eq('team')
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

    it 'returns the detail projection on create, update and avatar responses' do
      post "/api/v1/accounts/#{account.id}/autonomia/agents",
           params: {
             agent: {
               name: 'Manual novo', agent_type: 'custom', mode: 'manual', instruction: 'Atenda com clareza.'
             }
           }, headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:created)
      created_id = response.parsed_body.fetch('id')
      expect(response.parsed_body).to include('state', 'writes_external')

      patch "/api/v1/accounts/#{account.id}/autonomia/agents/#{created_id}",
            params: { agent: { greeting: 'Olá' } },
            headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to include('state', 'writes_external')

      delete "/api/v1/accounts/#{account.id}/autonomia/agents/#{created_id}/avatar",
             headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to include('state', 'writes_external')
    end

    it 'exposes the external-write warning only to a manager for the current agent' do
      Autonomia::Agents::Tool.create!(
        account: account, agent: agent, name: 'Atualiza CRM', slug: 'atualiza_crm',
        endpoint_url: 'https://example.com/crm', enabled: true
      )

      get "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}",
          headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['writes_external']).to be(true)

      viewer = create(:user, account: account, role: :agent)
      viewer_role = create(:custom_role, account: account, permissions: ['autonomia_view'])
      viewer.account_users.find_by!(account: account).update!(custom_role: viewer_role)

      get "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}",
          headers: viewer.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['writes_external']).to be(false)
    end

    it 'exposes the effective draft retention window from the shared config parser' do
      with_modified_env AUTONOMIA_DRAFT_REAP_HOURS: '12' do
        get "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}",
            headers: administrator.create_new_auth_token,
            as: :json
      end

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['draft_retention_hours']).to eq(12)
    end

    it 'falls back to the safe default when the draft retention ENV is zero' do
      with_modified_env AUTONOMIA_DRAFT_REAP_HOURS: '0' do
        get "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}",
            headers: administrator.create_new_auth_token,
            as: :json
      end

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['draft_retention_hours']).to eq(48)
    end

    it 'falls back to the safe default when the draft retention ENV is invalid' do
      with_modified_env AUTONOMIA_DRAFT_REAP_HOURS: 'not-a-number' do
        get "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}",
            headers: administrator.create_new_auth_token,
            as: :json
      end

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['draft_retention_hours']).to eq(48)
    end

    it 'exposes only available quote branches to an autonomy manager without insurance_view' do
      manager = create(:user, account: account, role: :agent)
      role = create(:custom_role, account: account, permissions: ['autonomia_manage'])
      manager.account_users.find_by!(account: account).update!(custom_role: role)

      expect(manager.account_users.find_by!(account: account).permission_granted?('insurance_view')).to be(false)

      get "/api/v1/accounts/#{account.id}/autonomia/agents/#{quote_agent.id}",
          headers: manager.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body.fetch('quote_branches')).to eq(
        [{ 'slug' => 'cotacao_auto', 'name' => 'Cotação de automóvel' }]
      )
      expect(response.parsed_body).not_to have_key('instruction')
      expect(response.parsed_body).not_to have_key('scaffold')
      expect(response.body).not_to include('agente_de_cotacao')
    end
  end
end
