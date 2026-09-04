require 'rails_helper'

RSpec.describe Autonomia::Agents::Tools::AsyncConfig do
  let(:account) { create(:account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom',
                                     status: :active, enabled: true, instruction: 'Atenda o cliente.')
  end
  let(:other_agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Outro bot', agent_type: 'custom',
                                     status: :active, enabled: true, instruction: 'Atenda o cliente.')
  end

  describe '.enabled?' do
    it 'is on by default, with no ENV and no agent override' do
      # Arrange / Act / Assert — o kill-switch é opt-out: ausente significa ligado.
      expect(described_class.enabled?(agent)).to be(true)
      expect(described_class.enabled?).to be(true)
    end

    it 'turns every agent off when the ENV kill-switch is false' do
      # Arrange / Act / Assert
      with_modified_env(AI_AGENT_ASYNC_TOOLS: 'false') do
        expect(described_class.enabled?(agent)).to be(false)
        expect(described_class.enabled?).to be(false)
      end
    end

    it 'turns off only the agent whose config says so' do
      # Arrange
      agent.update!(config: { 'async_tools' => false })

      # Act / Assert — o vizinho na mesma conta continua ligado.
      expect(described_class.enabled?(agent)).to be(false)
      expect(described_class.enabled?(other_agent)).to be(true)
    end

    it 'keeps ENV as master over an agent that enables it' do
      # Arrange
      agent.update!(config: { 'async_tools' => true })

      # Act / Assert
      with_modified_env(AI_AGENT_ASYNC_TOOLS: 'false') do
        expect(described_class.enabled?(agent)).to be(false)
      end
    end
  end

  describe '.intervals_for' do
    it 'falls back to the default progression without config' do
      # Arrange / Act / Assert
      expect(described_class.intervals_for(agent)).to eq(described_class::DEFAULT_INTERVALS)
      expect(described_class.intervals_for).to eq(described_class::DEFAULT_INTERVALS)
    end

    it 'clamps values outside the allowed range' do
      # Arrange — 0.5 abaixo do mínimo, 999 acima do máximo, 7 dentro da faixa.
      agent.update!(config: { 'async_poll_intervals' => [0.5, 999, 7] })

      # Act
      intervals = described_class.intervals_for(agent)

      # Assert
      expect(intervals).to eq([described_class::MIN_INTERVAL_SECONDS, described_class::MAX_INTERVAL_SECONDS, 7])
    end

    it 'falls back to the default when nothing in the list is a usable number' do
      # Arrange / Act / Assert — zero e texto viram 0.0 e somem; lista vazia cai no default.
      agent.update!(config: { 'async_poll_intervals' => [0] })
      expect(described_class.intervals_for(agent)).to eq(described_class::DEFAULT_INTERVALS)

      agent.update!(config: { 'async_poll_intervals' => ['abc'] })
      expect(described_class.intervals_for(agent)).to eq(described_class::DEFAULT_INTERVALS)
    end

    it 'cuts a list longer than the maximum' do
      # Arrange
      agent.update!(config: { 'async_poll_intervals' => Array.new(described_class::MAX_INTERVALS + 5, 5) })

      # Act
      intervals = described_class.intervals_for(agent)

      # Assert
      expect(intervals.length).to eq(described_class::MAX_INTERVALS)
      expect(intervals.uniq).to eq([5])
    end
  end

  describe '.interval_for' do
    it 'walks the configured progression by attempt' do
      # Arrange
      agent.update!(config: { 'async_poll_intervals' => [3, 8, 21] })

      # Act / Assert
      expect(described_class.interval_for(agent, 0)).to eq(3.seconds)
      expect(described_class.interval_for(agent, 1)).to eq(8.seconds)
      expect(described_class.interval_for(agent, 2)).to eq(21.seconds)
    end

    it 'repeats the last value after the end of the progression' do
      # Arrange
      agent.update!(config: { 'async_poll_intervals' => [3, 8, 21] })

      # Act / Assert — nada de estourar o índice nem voltar ao começo.
      expect(described_class.interval_for(agent, 3)).to eq(21.seconds)
      expect(described_class.interval_for(agent, 99)).to eq(21.seconds)
    end

    it 'does not blow up on a negative attempt' do
      # Arrange / Act / Assert — índice negativo pegaria o FIM da lista em Ruby; o clamp segura no começo.
      expect(described_class.interval_for(agent, -1)).to eq(described_class::DEFAULT_INTERVALS.first.seconds)
      expect(described_class.interval_for(agent, -99)).to eq(described_class::DEFAULT_INTERVALS.first.seconds)
    end

    it 'uses the default progression when the agent has no config' do
      # Arrange / Act / Assert
      expect(described_class.interval_for(agent, 0)).to eq(described_class::DEFAULT_INTERVALS[0].seconds)
      expect(described_class.interval_for(agent, 4)).to eq(described_class::DEFAULT_INTERVALS[4].seconds)
      expect(described_class.interval_for(nil, 0)).to eq(described_class::DEFAULT_INTERVALS[0].seconds)
    end
  end

  describe '.deadline_seconds_for' do
    it 'falls back to the default deadline without config' do
      # Arrange / Act / Assert
      expect(described_class.deadline_seconds_for(agent)).to eq(described_class::DEFAULT_DEADLINE_SECONDS.seconds)
      expect(described_class.deadline_seconds_for).to eq(described_class::DEFAULT_DEADLINE_SECONDS.seconds)
    end

    it 'clamps a deadline outside the allowed range' do
      # Arrange / Act / Assert
      agent.update!(config: { 'async_deadline_seconds' => 5 })
      expect(described_class.deadline_seconds_for(agent)).to eq(described_class::MIN_DEADLINE_SECONDS.seconds)

      agent.update!(config: { 'async_deadline_seconds' => 9999 })
      expect(described_class.deadline_seconds_for(agent)).to eq(described_class::MAX_DEADLINE_SECONDS.seconds)
    end

    it 'falls back to the default on a non numeric or zero deadline' do
      # Arrange / Act / Assert
      agent.update!(config: { 'async_deadline_seconds' => 'abc' })
      expect(described_class.deadline_seconds_for(agent)).to eq(described_class::DEFAULT_DEADLINE_SECONDS.seconds)

      agent.update!(config: { 'async_deadline_seconds' => 0 })
      expect(described_class.deadline_seconds_for(agent)).to eq(described_class::DEFAULT_DEADLINE_SECONDS.seconds)
    end

    it 'keeps a deadline already inside the range' do
      # Arrange
      agent.update!(config: { 'async_deadline_seconds' => 120 })

      # Act / Assert
      expect(described_class.deadline_seconds_for(agent)).to eq(120.seconds)
    end
  end
end
