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
      expect(payload.first['created_by_name']).to eq(administrator.name)
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
      expect(response.body).not_to include('guided v1')
      expect(version['instruction_hash']).to be_present
    end

    # #1428 — a versão agora guarda o agente inteiro (metadata), inclusive o andaime. O que é oculto
    # continua fora da API: nem a instrução, nem o andaime, nem o metadata saem.
    it 'never exposes the hidden instruction or scaffold kept in the whole-agent version' do
      # Arrange
      guided_agent.update!(scaffold: 'andaime secreto', greeting: 'oi')
      guided_agent.record_instruction_version!(reason: 'kb_refresh')

      # Act
      get "/api/v1/accounts/#{account.id}/autonomia/agents/#{guided_agent.id}/instruction_versions",
          headers: administrator.create_new_auth_token, as: :json

      # Assert
      version = response.parsed_body['payload'].first
      expect(version.keys).to match_array(%w[id created_at reason created_by_name instruction_hash])
      expect(response.body).not_to include('andaime secreto')
      expect(response.body).not_to include('guided v1')
    end

    # #1484 — a instrução gerada pelo Construtor (versão guiada) ficava visível quando o agente passava a
    # manual. Quem decide é o modo da VERSÃO, não o modo atual do agente.
    it 'never exposes the instruction of a guided version, even after the agent becomes manual' do
      # Arrange
      guided_agent.record_instruction_version!(reason: 'kb_refresh')
      guided_agent.update!(mode: :manual, instruction: 'escrita pelo dono')
      guided_agent.record_instruction_version!(reason: 'manual_edit', created_by: administrator)

      # Act
      get "/api/v1/accounts/#{account.id}/autonomia/agents/#{guided_agent.id}/instruction_versions",
          headers: administrator.create_new_auth_token, as: :json

      # Assert
      manual, guiada = response.parsed_body['payload']
      expect(manual['instruction']).to eq('escrita pelo dono')
      expect(guiada).not_to have_key('instruction')
      expect(response.body).not_to include('guided v1')
    end

    it 'exposes an old instruction-only version only when it was a manual edit' do
      # Arrange
      %w[kb_refresh manual_edit].each_with_index do |reason, indice|
        texto = "antiga #{indice}"
        manual_agent.instruction_versions.create!(account: account, reason: reason, instruction: texto,
                                                  instruction_hash: Digest::SHA256.hexdigest(texto))
      end

      # Act
      get "/api/v1/accounts/#{account.id}/autonomia/agents/#{manual_agent.id}/instruction_versions",
          headers: administrator.create_new_auth_token, as: :json

      # Assert
      por_motivo = response.parsed_body['payload'].index_by { |versao| versao['reason'] }
      expect(por_motivo['manual_edit']['instruction']).to eq('antiga 1')
      expect(por_motivo['kb_refresh']).not_to have_key('instruction')
    end

    # Revisão do #1428 (MÉDIO): versão do Construtor gravada com modo manual expunha a instrução gerada.
    it 'never exposes the instruction of a Builder version, even one recorded in manual mode' do
      # Arrange
      manual_agent.instruction_versions.create!(account: account, reason: 'builder_adjust', instruction: 'do construtor',
                                                instruction_hash: Digest::SHA256.hexdigest('do construtor'),
                                                metadata: { 'agente' => manual_agent.send(:retrato_da_versao) })

      # Act
      get "/api/v1/accounts/#{account.id}/autonomia/agents/#{manual_agent.id}/instruction_versions",
          headers: administrator.create_new_auth_token, as: :json

      # Assert
      versao = response.parsed_body['payload'].first
      expect(versao['reason']).to eq('builder_adjust')
      expect(versao).not_to have_key('instruction')
      expect(response.body).not_to include('do construtor')
    end

    # Revisão do #1428: a aplicação sem mudança fica no banco (rastro), mas não vira linha na lista.
    it 'keeps no-change versions out of the list' do
      # Arrange
      guided_agent.record_instruction_version!(reason: 'kb_refresh')
      guided_agent.instruction_versions.create!(account: account, reason: 'builder_adjust', instruction: 'guided v1',
                                                instruction_hash: 'x', metadata: { 'sem_mudanca' => true })

      # Act
      get "/api/v1/accounts/#{account.id}/autonomia/agents/#{guided_agent.id}/instruction_versions",
          headers: administrator.create_new_auth_token, as: :json

      # Assert
      expect(response.parsed_body['payload'].pluck('reason')).to eq(['kb_refresh'])
      expect(guided_agent.instruction_versions.count).to eq(2)
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
      expect(manual_agent.reload.instruction).to eq('manual v1')
      expect(manual_agent.instruction_versions.where(reason: 'rollback').count).to eq(1)
    end

    # Conferência do #1428, sonda A (#1484): um agente manual voltando a uma versão antiga do Construtor
    # (kb_refresh, sem retrato) saía manual, com a instrução gerada no GET do agente e na lista.
    it 'never shows the Builder instruction after a manual agent goes back to an old guided version' do
      # Arrange
      antiga = guided_agent.instruction_versions.create!(account: account, reason: 'kb_refresh', instruction: 'guided v1',
                                                         instruction_hash: Digest::SHA256.hexdigest('guided v1'))
      guided_agent.update!(mode: :manual, instruction: 'escrita pelo dono')

      # Act
      post "/api/v1/accounts/#{account.id}/autonomia/agents/#{guided_agent.id}" \
           "/instruction_versions/#{antiga.id}/restore",
           headers: administrator.create_new_auth_token, as: :json

      # Assert
      expect(response.body).not_to include('guided v1')
      get "/api/v1/accounts/#{account.id}/autonomia/agents/#{guided_agent.id}/instruction_versions",
          headers: administrator.create_new_auth_token, as: :json
      expect(response.body).not_to include('guided v1')
      get "/api/v1/accounts/#{account.id}/autonomia/agents/#{guided_agent.id}",
          headers: administrator.create_new_auth_token, as: :json
      expect(response.parsed_body['mode']).to eq('guided')
      expect(response.body).not_to include('guided v1')
    end

    # Revisão do #1428 (MÉDIO): voltar a uma versão do Construtor gravada em modo manual deixava a instrução
    # gerada num agente manual.
    it 'puts the agent back in guided mode when going back to a Builder version recorded in manual mode' do
      # Arrange
      retrato = manual_agent.send(:retrato_da_versao)
      versao = manual_agent.instruction_versions.create!(account: account, reason: 'builder_adjust',
                                                         instruction: 'do construtor',
                                                         instruction_hash: Digest::SHA256.hexdigest('do construtor'),
                                                         metadata: { 'agente' => retrato })
      expect(retrato['mode']).to eq('manual')

      # Act
      post "/api/v1/accounts/#{account.id}/autonomia/agents/#{manual_agent.id}" \
           "/instruction_versions/#{versao.id}/restore",
           headers: administrator.create_new_auth_token, as: :json

      # Assert
      expect(response).to have_http_status(:success)
      expect(response.body).not_to include('do construtor')
      expect(manual_agent.reload.mode).to eq('guided')
      get "/api/v1/accounts/#{account.id}/autonomia/agents/#{manual_agent.id}/instruction_versions",
          headers: administrator.create_new_auth_token, as: :json
      expect(response.body).not_to include('do construtor')
    end

    it 'gives back every field kept in the version and keeps the hidden ones out of the response' do
      # Arrange
      guided_agent.update!(scaffold: 'andaime v1', greeting: 'oi v1', tone: 'tom v1')
      v1 = guided_agent.record_instruction_version!(reason: 'kb_refresh')
      guided_agent.update!(instruction: 'guided v2', scaffold: 'andaime v2', greeting: 'oi v2', tone: 'tom v2')

      # Act
      post "/api/v1/accounts/#{account.id}/autonomia/agents/#{guided_agent.id}" \
           "/instruction_versions/#{v1.id}/restore",
           headers: administrator.create_new_auth_token, as: :json

      # Assert
      expect(response).to have_http_status(:success)
      guided_agent.reload
      expect([guided_agent.instruction, guided_agent.scaffold, guided_agent.greeting, guided_agent.tone])
        .to eq(['guided v1', 'andaime v1', 'oi v1', 'tom v1'])
      expect(response.body).not_to include('andaime v1')
      expect(response.body).not_to include('guided v1')
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
end
