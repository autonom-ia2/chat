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

  # A INSTRUÇÃO DO AGENTE DE COTAÇÃO É MANTIDA PELA AUTONOM.IA (#380, rodada de correção). Depois de
  # #380 o prompt da Lia é o arquivo do deploy com as escolhas da corretora; a coluna `instruction`
  # virou retrato do nascimento. Todo caminho que ainda escrevia a coluna depois do nascimento
  # (edição manual, rollback G2, refresh de KB, "Ajustar com IA") passaria a gravar um texto que ela
  # não lê — o cartão mentiria. A regra tem UM predicado no model e cada escritor a consulta.
  describe 'instrução mantida pela Autonom.ia (#380)' do
    let(:lia) do
      described_class.create!(account: account, name: 'Lia', agent_type: 'insurance_quote',
                              instruction: 'retrato do nascimento')
    end

    it 'é o Agente de Cotação, e só ele' do
      expect(lia.instrucao_mantida?).to be(true)
      expect(build_agent(agent_type: 'support').instrucao_mantida?).to be(false)
    end

    # O modo manual é o que expõe e aceita a instrução pela API; o agente de cotação nunca entra nele.
    it 'não aceita o modo manual' do
      # Act
      lia.mode = :manual
      lia.validate

      # Assert
      expect(lia.errors[:mode]).to be_present
      expect(build_agent(agent_type: 'support', mode: :manual)).to be_valid
    end

    it 'não é reescrita pelo refresh de conhecimento' do
      expect { lia.refresh_instruction!('reescrita pela KB', expected_instruction: 'retrato do nascimento') }
        .to raise_error(described_class::InstrucaoMantida)
      expect(lia.reload.instruction).to eq('retrato do nascimento')
    end

    it 'não volta por rollback' do
      # Arrange — o snapshot em si é permitido (é auditoria, não escrita da coluna).
      versao = lia.record_instruction_version!(reason: 'kb_refresh')

      # Act / Assert
      expect { lia.restore_instruction!(versao) }.to raise_error(described_class::InstrucaoMantida)
      expect(lia.reload.instruction).to eq('retrato do nascimento')
      expect(lia.instruction_versions.where(reason: 'rollback')).not_to exist
    end

    it 'não recebe a config do Construtor conversacional' do
      expect { lia.apply_builder_config!('token', { instruction: 'gerada pelo Construtor' }) }
        .to raise_error(described_class::InstrucaoMantida)
      expect(lia.reload.instruction).to eq('retrato do nascimento')
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
