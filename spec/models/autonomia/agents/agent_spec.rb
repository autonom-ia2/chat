require 'rails_helper'

RSpec.describe Autonomia::Agents::Agent do
  let(:account) { create(:account) }

  def build_agent(attrs = {})
    described_class.new({ account: account, name: 'Ana', agent_type: 'sdr' }.merge(attrs))
  end

  describe 'tone length' do
    # Regressão real: `tone` era string, então o teto genérico do ApplicationRecord (255) derrubava
    # a gravação INTEIRA da config quando o Construtor escrevia um tom com mais nuance.
    it 'accepts a tone longer than the generic string cap' do
      # Arrange
      agent = build_agent(tone: 'a' * 300)

      # Act / Assert
      expect(agent).to be_valid
    end

    it 'rejects a tone above the agent cap' do
      # Arrange
      agent = build_agent(tone: 'a' * (described_class::MAX_TONE_LENGTH + 1))

      # Act
      agent.validate

      # Assert
      expect(agent.errors[:tone]).to be_present
    end
  end

  describe 'instruction length' do
    it 'accepts an instruction longer than the generic text cap' do
      # Arrange
      agent = build_agent(instruction: 'a' * 25_000)

      # Act / Assert
      expect(agent).to be_valid
    end

    it 'rejects an instruction above the agent cap' do
      # Arrange
      agent = build_agent(instruction: 'a' * (described_class::MAX_INSTRUCTION_LENGTH + 1))

      # Act
      agent.validate

      # Assert
      expect(agent.errors[:instruction]).to be_present
    end
  end
end
