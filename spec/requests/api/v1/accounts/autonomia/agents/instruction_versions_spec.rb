require 'rails_helper'

# G2 — endpoint de histórico + rollback da instrução. Escopo por conta/agente (404 cross-account),
# IP OCULTO (texto só em modo manual) e rollback atômico.
RSpec.describe 'Autonomia agent instruction versions', type: :request do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:administrator) { create(:user, account: account, role: :administrator) }

  let(:manual_agent) do
    Autonomia::Agents::Agent.create!(
      account: account, name: 'Manual', agent_type: 'custom', mode: :manual, instruction: 'manual v1'
    )
  end

  let(:guided_agent) do
    Autonomia::Agents::Agent.create!(
      account: account, name: 'Guiado', agent_type: 'custom', mode: :guided, instruction: 'guided v1'
    )
  end

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true' do
      example.run
    end
  end

  describe 'GET .../instruction_versions' do
    it 'lists versions scoped to the account, newest first' do
      # Arrange
      manual_agent.record_instruction_version!(reason: 'manual_edit', created_by: administrator)
      manual_agent.update!(instruction: 'manual v2')
      manual_agent.record_instruction_version!(reason: 'manual_edit', created_by: administrator)

      # Act
      get "/api/v1/accounts/#{account.id}/autonomia/agents/#{manual_agent.id}/instruction_versions",
          headers: administrator.create_new_auth_token, as: :json

      # Assert
      expect(response).to have_http_status(:success)
      payload = response.parsed_body['payload']
      expect(payload.size).to eq(2)
      expect(payload.first['reason']).to eq('manual_edit')
      expect(payload.first['origin']).to eq('manual')
      expect(payload.first['created_by_name']).to eq(administrator.name)
    end

    it 'marks the effective manual version as current' do
      manual_agent.record_instruction_version!(reason: 'manual_edit', created_by: administrator)
      manual_agent.update!(instruction: 'manual v2')
      current = manual_agent.record_instruction_version!(reason: 'manual_edit', created_by: administrator)

      get "/api/v1/accounts/#{account.id}/autonomia/agents/#{manual_agent.id}/instruction_versions",
          headers: administrator.create_new_auth_token, as: :json

      payload = response.parsed_body.fetch('payload')
      expect(payload.find { |entry| entry['id'] == current.id }).to include('current' => true)
      expect(payload.find { |entry| entry['reason'] == 'manual_edit' && entry['id'] != current.id })
        .to include('current' => false)
    end

    it 'does not mark the before-manual snapshot as current' do
      guided_agent.update!(scaffold: 'Andaime guiado')
      builder = guided_agent.record_instruction_version!(reason: 'builder', created_by: administrator)
      snapshot = guided_agent.record_instruction_version!(reason: 'before_manual', created_by: administrator, force: true)

      get "/api/v1/accounts/#{account.id}/autonomia/agents/#{guided_agent.id}/instruction_versions",
          headers: administrator.create_new_auth_token, as: :json

      payload = response.parsed_body.fetch('payload')
      expect(payload.find { |entry| entry['id'] == builder.id }).to include('current' => true)
      expect(payload.find { |entry| entry['id'] == snapshot.id }).to include('current' => false)
    end

    it 'includes the instruction text for a manual agent' do
      # Arrange
      manual_agent.record_instruction_version!(reason: 'manual_edit', created_by: administrator)

      # Act
      get "/api/v1/accounts/#{account.id}/autonomia/agents/#{manual_agent.id}/instruction_versions",
          headers: administrator.create_new_auth_token, as: :json

      # Assert
      expect(response.parsed_body['payload'].first['instruction']).to eq('manual v1')
    end

    it 'hides the instruction text for a guided agent (IP guard)' do
      # Arrange
      guided_agent.record_instruction_version!(reason: 'kb_refresh')

      # Act
      get "/api/v1/accounts/#{account.id}/autonomia/agents/#{guided_agent.id}/instruction_versions",
          headers: administrator.create_new_auth_token, as: :json

      # Assert
      version = response.parsed_body['payload'].first
      expect(version).not_to have_key('instruction')
      expect(version['origin']).to eq('guided')
      expect(response.body).not_to include('guided v1')
      expect(version['instruction_hash']).to be_present
    end

    it 'hides a guided snapshot even after the current agent switches to manual mode' do
      guided_agent.update!(scaffold: 'Andaime guiado')
      version = guided_agent.record_instruction_version!(reason: 'before_manual', created_by: administrator, force: true)
      guided_agent.update!(mode: :manual, instruction: 'manual v1', scaffold: 'Andaime manual')

      get "/api/v1/accounts/#{account.id}/autonomia/agents/#{guided_agent.id}/instruction_versions",
          headers: administrator.create_new_auth_token, as: :json

      payload = response.parsed_body.fetch('payload').find { |entry| entry['id'] == version.id }
      expect(payload).not_to have_key('instruction')
    end

    it 'hides an old rollback without origin metadata because its authorship is ambiguous' do
      version = manual_agent.instruction_versions.create!(
        account: account,
        instruction: 'old rollback',
        instruction_hash: Digest::SHA256.hexdigest('old rollback'),
        reason: 'rollback',
        metadata: {}
      )

      get "/api/v1/accounts/#{account.id}/autonomia/agents/#{manual_agent.id}/instruction_versions",
          headers: administrator.create_new_auth_token, as: :json

      payload = response.parsed_body.fetch('payload').find { |entry| entry['id'] == version.id }
      expect(payload).not_to have_key('instruction')
    end

    it 'refuses to restore an old rollback whose authorship is ambiguous' do
      version = manual_agent.instruction_versions.create!(
        account: account,
        instruction: 'old rollback',
        instruction_hash: Digest::SHA256.hexdigest('old rollback'),
        reason: 'rollback',
        metadata: {}
      )

      post "/api/v1/accounts/#{account.id}/autonomia/agents/#{manual_agent.id}" \
           "/instruction_versions/#{version.id}/restore",
           headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include('code' => 'unrestorable_version')
      expect(manual_agent.reload.instruction).to eq('manual v1')
    end

    it '404s an agent from another account' do
      # Arrange
      other_account = create(:account, internal_attributes: { 'autonomia_agents_enabled' => true })
      other_agent = Autonomia::Agents::Agent.create!(
        account: other_account, name: 'Alheio', agent_type: 'custom', mode: :manual, instruction: 'x'
      )

      # Act
      get "/api/v1/accounts/#{account.id}/autonomia/agents/#{other_agent.id}/instruction_versions",
          headers: administrator.create_new_auth_token, as: :json

      # Assert
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST .../instruction_versions/:version_id/restore' do
    it 'restores the agent instruction to the version text' do
      # Arrange
      v1 = manual_agent.record_instruction_version!(reason: 'manual_edit', created_by: administrator)
      manual_agent.update!(instruction: 'manual v2')

      # Act
      post "/api/v1/accounts/#{account.id}/autonomia/agents/#{manual_agent.id}" \
           "/instruction_versions/#{v1.id}/restore",
           headers: administrator.create_new_auth_token, as: :json

      # Assert
      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to include('state', 'writes_external')
      expect(manual_agent.reload.instruction).to eq('manual v1')
      expect(manual_agent.instruction_versions.where(reason: 'rollback').count).to eq(1)
    end

    # #380 (rodada de correção) — a instrução do Agente de Cotação é mantida pela Autonom.ia; o
    # rollback escreveria uma coluna que ela não lê e o histórico mentiria "restaurado".
    it 'refuses to roll back the quote agent instruction, which is maintained by Autonom.ia' do
      # Arrange
      lia = Autonomia::Insurance::QuoteAgent::Builder.new(account: account, nome_agente: 'Lia', nome_corretora: 'Sena').call
      nascimento = lia.instruction
      versao = lia.record_instruction_version!(reason: 'kb_refresh')
      lia.update!(instruction: 'coluna envelhecida')

      # Act
      post "/api/v1/accounts/#{account.id}/autonomia/agents/#{lia.id}" \
           "/instruction_versions/#{versao.id}/restore",
           headers: administrator.create_new_auth_token, as: :json

      # Assert
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq(I18n.t('autonomia.agents.instrucao_mantida', raise: true))
      expect(lia.reload.instruction).to eq('coluna envelhecida')
      expect(lia.instruction_versions.where(reason: 'rollback')).not_to exist
      expect(nascimento).to include('Você é Lia')
    end

    it '404s a version that belongs to another agent' do
      # Arrange
      foreign = guided_agent.record_instruction_version!(reason: 'kb_refresh')

      # Act
      post "/api/v1/accounts/#{account.id}/autonomia/agents/#{manual_agent.id}" \
           "/instruction_versions/#{foreign.id}/restore",
           headers: administrator.create_new_auth_token, as: :json

      # Assert
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'PATCH .../agents/:id mode' do
    it 'restores the latest guided version when a manual agent returns to guided mode' do
      guided_agent.update!(scaffold: 'Andaime guiado')
      guided_agent.record_instruction_version!(reason: 'builder', created_by: administrator)
      guided_agent.update!(mode: :manual, instruction: 'manual v1', scaffold: 'Andaime manual')

      patch "/api/v1/accounts/#{account.id}/autonomia/agents/#{guided_agent.id}",
            params: { agent: { mode: 'guided' } },
            headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(guided_agent.reload).to have_attributes(mode: 'guided', instruction: 'guided v1', scaffold: 'Andaime guiado')
      expect(guided_agent.instruction_versions.where(reason: 'rollback')).to exist
    end

    it 'returns a stable error when no guided version with scaffold is available' do
      manual_agent.record_instruction_version!(reason: 'manual_edit', created_by: administrator)

      patch "/api/v1/accounts/#{account.id}/autonomia/agents/#{manual_agent.id}",
            params: { agent: { mode: 'guided' } },
            headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include('code' => 'no_guided_version')
      expect(manual_agent.reload).to have_attributes(mode: 'manual', instruction: 'manual v1')
    end

    it 'rejects an empty manual instruction at the request boundary' do
      patch "/api/v1/accounts/#{account.id}/autonomia/agents/#{guided_agent.id}",
            params: { agent: { mode: 'manual', instruction: '   ' } },
            headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include('code' => 'manual_instruction_required', 'key' => 'instruction')
    end

    it 'rejects internal mode before recording a guided snapshot when a channel is connected' do
      link_agent_to_channel(guided_agent)
      version_ids = guided_agent.instruction_versions.pluck(:id)

      with_modified_env CRM_KANBAN_ENABLED: 'true', CRM_COPILOT_ENABLED: 'true', CRM_AI_ENABLED: 'true' do
        patch "/api/v1/accounts/#{account.id}/autonomia/agents/#{guided_agent.id}",
              params: { agent: { mode: 'manual', instruction: 'manual v2', actuation: 'internal' } },
              headers: administrator.create_new_auth_token, as: :json
      end

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include('code' => 'internal_with_channels')
      expect(guided_agent.reload).to have_attributes(mode: 'guided', actuation: 'external', instruction: 'guided v1')
      expect(guided_agent.instruction_versions.pluck(:id)).to eq(version_ids)
    end

    it 'rejects internal mode before restoring guided state when a channel is connected' do
      guided_agent.update!(scaffold: 'Andaime guiado')
      guided_agent.record_instruction_version!(reason: 'builder', created_by: administrator)
      guided_agent.update!(mode: :manual, instruction: 'manual v1', scaffold: 'Andaime manual')
      link_agent_to_channel(guided_agent)
      version_ids = guided_agent.instruction_versions.pluck(:id)

      with_modified_env CRM_KANBAN_ENABLED: 'true', CRM_COPILOT_ENABLED: 'true', CRM_AI_ENABLED: 'true' do
        patch "/api/v1/accounts/#{account.id}/autonomia/agents/#{guided_agent.id}",
              params: { agent: { mode: 'guided', actuation: 'internal' } },
              headers: administrator.create_new_auth_token, as: :json
      end

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include('code' => 'internal_with_channels')
      expect(guided_agent.reload).to have_attributes(mode: 'manual', actuation: 'external', instruction: 'manual v1')
      expect(guided_agent.instruction_versions.pluck(:id)).to eq(version_ids)
    end
  end

  def link_agent_to_channel(agent)
    inbox = create(:inbox, account: agent.account)
    mirror = AgentBot.create!(account: agent.account, name: agent.name, bot_type: :webhook, outgoing_url: nil)
    Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: agent.account, agent_bot: mirror)
  end
end
