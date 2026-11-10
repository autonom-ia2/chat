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
        %w[handoff_strategy handoff_target_id with_knowledge knowledge_confidence knowledge_summary]
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

    # #2490: a Confira de um rascunho reaberto lê o canal que o dono pediu ao Construtor.
    it 'exposes the channel the owner asked the Builder for' do
      agent.update!(config: agent.config.merge('canal_pedido' => 'instagram'))

      get "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}", headers: administrator.create_new_auth_token, as: :json

      expect(response.parsed_body['config']['canal_pedido']).to eq('instagram')
    end

    # #2858 F3: a Confira de um rascunho reaberto mostra "já vem com" a partir da escolha do Construtor; a sugestão
    # guardada e as dispensadas ficam só no servidor.
    it 'exposes the tools the Builder chose, not the stored suggestion' do
      agent.update!(config: agent.config.merge('ferramentas_sugeridas' => %w[fipe], 'prontas_sugestao' => { 'chaves' => %w[cep] }))

      get "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}", headers: administrator.create_new_auth_token, as: :json

      expect(response.parsed_body['config']).to include('ferramentas_sugeridas' => %w[fipe])
      expect(response.parsed_body['config']).not_to have_key('prontas_sugestao')
    end
  end

  describe 'PATCH /api/v1/accounts/:account_id/autonomia/agents/:id' do
    # #2490: só o Construtor escreve o canal pedido; a API de edição não o troca.
    it 'keeps the channel asked to the Builder when the config is saved through the API' do
      agent.update!(config: agent.config.merge('canal_pedido' => 'instagram'))

      patch "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}",
            params: { agent: { config: { canal_pedido: 'whatsapp', handoff_target_id: 7 } } },
            headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(agent.reload.config).to include('canal_pedido' => 'instagram', 'handoff_target_id' => 7)
    end
  end
end
