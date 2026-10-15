require 'rails_helper'

RSpec.describe Autonomia::Agents::AgentInbox do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Agente', agent_type: 'custom')
  end
  let(:agent_bot) { AgentBot.create!(account: account, name: 'Espelho') }

  def build_link(overrides = {})
    described_class.new({ account: account, inbox: inbox, agent: agent, agent_bot: agent_bot }.merge(overrides))
  end

  describe 'tenancy validation' do
    it 'accepts a link where agent, inbox and agent_bot belong to the account' do
      # Arrange / Act
      link = build_link

      # Assert
      expect(link).to be_valid
    end

    it 'rejects an agent from another account' do
      # Arrange
      foreign_agent = Autonomia::Agents::Agent.create!(account: other_account, name: 'Alheio', agent_type: 'custom')

      # Act
      link = build_link(agent: foreign_agent)

      # Assert
      expect(link).not_to be_valid
      expect(link.errors[:agent]).to include('must belong to the same account')
    end

    it 'rejects an inbox from another account' do
      # Arrange
      foreign_inbox = create(:inbox, account: other_account)

      # Act
      link = build_link(inbox: foreign_inbox)

      # Assert
      expect(link).not_to be_valid
      expect(link.errors[:inbox]).to include('must belong to the same account')
    end

    it 'rejects an agent_bot from another account' do
      # Arrange
      foreign_bot = AgentBot.create!(account: other_account, name: 'Bot alheio')

      # Act
      link = build_link(agent_bot: foreign_bot)

      # Assert
      expect(link).not_to be_valid
      expect(link.errors[:agent_bot]).to include('must belong to the same account')
    end
  end

  # #1433 F1a — papel na caixa: a porta atende primeiro (uma por caixa); a área recebe quando alguém passa a conversa.
  describe 'papel na caixa' do
    let(:porta) { build_link.tap(&:save!) }
    let(:outro_agente) { Autonomia::Agents::Agent.create!(account: account, name: 'Equipe', agent_type: 'custom') }
    let(:bot_da_area) { AgentBot.create!(account: account, name: 'Espelho da área') }

    def area(overrides = {})
      build_link({ agent: outro_agente, agent_bot: bot_da_area, papel: 'area' }.merge(overrides))
    end

    it 'nasce porta e separa os vínculos pelos escopos .porta e .area' do
      porta
      vinculo_da_area = area.tap(&:save!)

      expect(porta.papel).to eq('porta')
      expect(described_class.porta).to contain_exactly(porta)
      expect(described_class.area).to contain_exactly(vinculo_da_area)
    end

    it 'aceita só os papéis porta e area' do
      expect(build_link(papel: 'gerente')).not_to be_valid
    end

    # #1433: sem porta, a área entra na caixa só de pessoas; #1648 (decisão do Rodrigo de 15/10, opção B): também na caixa
    # com agente de outro sistema atendendo primeiro.
    it 'aceita área em caixa só de pessoas e em caixa sem porta com agente de outro sistema' do
      expect(area).to be_valid

      AgentBotInbox.create!(inbox: inbox, agent_bot: AgentBot.create!(account: account, name: 'Parceiro'), account: account)
      expect(area).to be_valid
    end

    it 'espelho de agente, apagado ou de outra caixa, não é agente de outro sistema; bot de webhook é (#1648)' do
      outra = create(:inbox, account: account)
      AgentBotInbox.create!(inbox: outra, agent_bot: agent_bot, account: account)
      porta.update_columns(deleted_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      de_outro_sistema = -> { Autonomia::Agents::QuemAtendeACaixa.robos_de_outro_sistema(outra).pluck(:agent_bot_id) }

      expect(de_outro_sistema.call).to be_empty

      n8n = AgentBot.create!(account: account, name: 'Automação')
      AgentBotInbox.create!(inbox: outra, agent_bot: n8n, account: account)
      expect(de_outro_sistema.call).to eq([n8n.id])
    end

    it 'aceita área em caixa com porta ativa, e mais de uma área por caixa' do
      porta
      area.save!
      terceiro = Autonomia::Agents::Agent.create!(account: account, name: 'Financeiro', agent_type: 'custom')

      expect(area(agent: terceiro, agent_bot: AgentBot.create!(account: account, name: 'Espelho 3'))).to be_valid
    end

    it 'recusa o mesmo agente como porta e área na mesma caixa' do
      porta

      expect(area(agent: agent)).not_to be_valid
    end

    it 'continua recusando duas portas na mesma caixa' do
      porta

      expect(build_link(agent: outro_agente, agent_bot: bot_da_area)).not_to be_valid
    end
  end
end
