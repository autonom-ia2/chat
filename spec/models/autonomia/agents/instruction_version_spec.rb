require 'rails_helper'

# G2 — versionamento da instrução: snapshot + rollback atômico, com idempotência por hash e
# blindagem de tenancy (uma versão de outro agente nunca restaura neste).
RSpec.describe Autonomia::Agents::InstructionVersion, type: :model do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  let(:agent) do
    Autonomia::Agents::Agent.create!(
      account: account, name: 'Agente', agent_type: 'custom', mode: :manual, instruction: 'v1'
    )
  end

  # O HISTÓRICO GUARDA O QUE O AGENTE ACEITA (21/09/2026). O agente declara instrução de até
  # `Agent::MAX_INSTRUCTION_LENGTH`; a versão não declarava nada e herdava o teto genérico de texto do
  # `ApplicationRecord` (20.000). Instrução entre os dois era salva no agente e perdida no histórico, com um
  # erro só no log. Apareceu quando a instrução do Agente de Cotação passou de 20.000 caracteres.
  describe 'o tamanho da instrucao guardada' do
    it 'guarda uma instrucao maior que o teto generico de texto, ate o teto do agente' do
      # Arrange
      longa = 'a' * Autonomia::Agents::Agent::MAX_INSTRUCTION_LENGTH
      agent.update!(instruction: longa)

      # Act
      version = agent.record_instruction_version!(reason: 'manual_edit', created_by: user)

      # Assert
      expect(version).to be_persisted
      expect(version.instruction.length).to eq(Autonomia::Agents::Agent::MAX_INSTRUCTION_LENGTH)
    end

    it 'recusa acima do teto do agente' do
      versao = described_class.new(agent: agent, account: account, reason: 'manual_edit', instruction_hash: 'x',
                                   instruction: 'a' * (Autonomia::Agents::Agent::MAX_INSTRUCTION_LENGTH + 1))

      expect(versao).not_to be_valid
    end
  end

  describe '#record_instruction_version!' do
    it 'creates a version row snapshotting the current instruction, reason and author' do
      # Act
      version = agent.record_instruction_version!(reason: 'manual_edit', created_by: user)

      # Assert
      expect(version).to be_persisted
      expect(version.instruction).to eq('v1')
      expect(version.reason).to eq('manual_edit')
      expect(version.created_by).to eq(user)
      expect(version.account).to eq(account)
      expect(version.instruction_hash).to eq(Digest::SHA256.hexdigest('v1'))
      expect(version.metadata).to include('agent_name' => 'Agente')
    end

    it 'marks Builder snapshots as guided so a later rename can be explained' do
      agent.update!(mode: :guided, scaffold: 'Andaime guiado')
      version = agent.record_instruction_version!(reason: 'builder', created_by: user)

      expect(version.metadata).to include('origin' => 'guided', 'agent_name' => 'Agente', 'scaffold' => agent.scaffold)
    end

    it 'can force the guided snapshot recorded immediately before switching to manual' do
      first = agent.record_instruction_version!(reason: 'builder', created_by: user)
      second = agent.record_instruction_version!(reason: 'before_manual', created_by: user, force: true)

      expect(first.instruction_hash).to eq(second.instruction_hash)
      expect(second.reason).to eq('before_manual')
      expect(second.metadata).to include('origin' => 'guided')
      expect(agent.instruction_versions.count).to eq(2)
    end

    it 'records the manual origin and scaffold for user-authored text' do
      agent.update!(scaffold: 'Andaime manual')

      version = agent.record_instruction_version!(reason: 'manual_edit', created_by: user)

      expect(version).to be_manual_origin
      expect(version.metadata).to include('scaffold' => 'Andaime manual')
    end

    it 'is idempotent: a second call with the same instruction hash is a no-op' do
      # Arrange
      agent.record_instruction_version!(reason: 'manual_edit', created_by: user)

      # Act
      second = agent.record_instruction_version!(reason: 'kb_refresh')

      # Assert
      expect(second).to be_nil
      expect(agent.instruction_versions.count).to eq(1)
    end

    it 'records a new row when the instruction text changed' do
      # Arrange
      agent.record_instruction_version!(reason: 'manual_edit', created_by: user)

      # Act
      agent.update!(instruction: 'v2')
      agent.record_instruction_version!(reason: 'manual_edit', created_by: user)

      # Assert
      expect(agent.instruction_versions.count).to eq(2)
    end

    it 'is a no-op when the agent has no instruction' do
      # Arrange
      blank_agent = Autonomia::Agents::Agent.create!(
        account: account, name: 'Rascunho', agent_type: 'custom'
      )

      # Act / Assert
      expect(blank_agent.record_instruction_version!(reason: 'manual_edit')).to be_nil
      expect(blank_agent.instruction_versions.count).to eq(0)
    end
  end

  describe '#restore_instruction!' do
    it 'sets the instruction to the version text and records a rollback version' do
      # Arrange
      v1 = agent.record_instruction_version!(reason: 'manual_edit', created_by: user)
      agent.update!(instruction: 'v2')

      # Act
      result = agent.restore_instruction!(v1, created_by: user)

      # Assert
      expect(result).to be_truthy
      expect(agent.reload.instruction).to eq('v1')
      rollback = agent.instruction_versions.order(:created_at).last
      expect(rollback.reason).to eq('rollback')
      expect(rollback.instruction).to eq('v1')
      expect(rollback.created_by).to eq(user)
    end

    it 'restores a guided version with its scaffold and guided mode' do
      agent.update!(mode: :guided, instruction: 'guided v1', scaffold: 'Andaime guiado')
      guided = agent.record_instruction_version!(reason: 'builder', created_by: user)
      agent.update!(mode: :manual, instruction: 'manual v2', scaffold: 'Andaime manual')

      expect(agent.restore_instruction!(guided, created_by: user)).to be(true)

      expect(agent.reload).to have_attributes(mode: 'guided', instruction: 'guided v1', scaffold: 'Andaime guiado')
      expect(agent.instruction_versions.order(:id).last.metadata).to include('origin' => 'guided', 'scaffold' => 'Andaime guiado')
    end

    it 'restores a manual version as manual and exposes its text only for manual origin' do
      agent.update!(mode: :manual, instruction: 'manual v1', scaffold: 'Andaime manual')
      manual = agent.record_instruction_version!(reason: 'manual_edit', created_by: user)
      agent.update!(mode: :guided, instruction: 'guided v2', scaffold: 'Andaime guiado')

      expect(agent.restore_instruction!(manual, created_by: user)).to be(true)

      expect(agent.reload).to have_attributes(mode: 'manual', instruction: 'manual v1', scaffold: 'Andaime manual')
      expect(agent.instruction_versions.order(:id).last).to be_manual_origin
    end

    it 'rejects a version that belongs to another agent' do
      # Arrange
      other_agent = Autonomia::Agents::Agent.create!(
        account: account, name: 'Outro', agent_type: 'custom', mode: :manual, instruction: 'x'
      )
      foreign = other_agent.record_instruction_version!(reason: 'manual_edit')

      # Act
      result = agent.restore_instruction!(foreign, created_by: user)

      # Assert
      expect(result).to be(false)
      expect(agent.reload.instruction).to eq('v1')
    end
  end
end
