require 'rails_helper'

RSpec.describe Autonomia::Agents::Tools::Bound do
  let(:account) { create(:account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(
      account: account, name: 'Bot', agent_type: 'custom', status: :active,
      enabled: true, instruction: 'Atenda.'
    )
  end

  def create_http_tool(slug)
    Autonomia::Agents::Tool.create!(
      account: account, agent: agent, name: slug.humanize, slug: slug,
      endpoint_url: "https://exemplo.test/#{slug}", param_schema: []
    )
  end

  describe '.for_agent' do
    it 'lists registered tools first and native tools after' do
      # Arrange
      create_http_tool('consultar_estoque')
      allow(Autonomia::Agents::Tools::Registry).to receive(:for_agent)
        .and_return([Autonomia::Agents::Tools::Native::InsuranceCapabilities])

      # Act
      bound = described_class.for_agent(agent)

      # Assert
      expect(bound.map(&:slug)).to eq(%w[consultar_estoque consultar_produtos_cotacao])
      expect(bound.map(&:native?)).to eq([false, true])
    end

    it 'skips a disabled registered tool' do
      create_http_tool('consultar_estoque').update!(enabled: false)
      allow(Autonomia::Agents::Tools::Registry).to receive(:for_agent).and_return([])

      expect(described_class.for_agent(agent)).to be_empty
    end
  end

  describe '#execute' do
    it 'runs a registered tool through the HTTP executor' do
      # Arrange
      tool = create_http_tool('consultar_estoque')
      executor = instance_double(Autonomia::Agents::Tools::HttpExecutor, call: '{"estoque":3}')
      allow(Autonomia::Agents::Tools::HttpExecutor).to receive(:new).and_return(executor)
      bound = described_class.new(agent: agent, record: tool)

      # Act / Assert
      expect(bound.execute({ 'arguments' => '{}' })).to eq('{"estoque":3}')
    end

    it 'names an HTTP failure instead of raising, keeping the status' do
      tool = create_http_tool('consultar_estoque')
      allow(Autonomia::Agents::Tools::HttpExecutor).to receive(:new)
        .and_raise(Autonomia::Agents::Tools::HttpExecutor::Error, 'tool_http_error: 503 Service Unavailable')
      bound = described_class.new(agent: agent, record: tool)

      expect(bound.execute({ 'arguments' => '{}' })).to eq({ error: 'tool_http_error: 503' }.to_json)
    end

    # Defesa na fronteira com o modelo: hoje o executor só manda status e frase padrão, mas o dia
    # em que alguém incluir URL ou corpo de resposta na exceção não pode virar vazamento silencioso.
    it 'drops free text from an HTTP failure message, keeping only category and status' do
      tool = create_http_tool('consultar_estoque')
      leaky = 'tool_http_error: 500 em https://api.exemplo.test/v1?token=segredo123 corpo={"senha":"x"}'
      allow(Autonomia::Agents::Tools::HttpExecutor).to receive(:new)
        .and_raise(Autonomia::Agents::Tools::HttpExecutor::Error, leaky)
      bound = described_class.new(agent: agent, record: tool)

      output = bound.execute({ 'arguments' => '{}' })

      expect(output).to eq({ error: 'tool_http_error: 500' }.to_json)
      expect(output).not_to include('segredo123')
      expect(output).not_to include('exemplo.test')
      expect(output).not_to include('senha')
    end

    it 'falls back to a bare category when the message carries no status' do
      tool = create_http_tool('consultar_estoque')
      allow(Autonomia::Agents::Tools::HttpExecutor).to receive(:new)
        .and_raise(Autonomia::Agents::Tools::HttpExecutor::Error, 'tool_execution_error: liquid_error')
      bound = described_class.new(agent: agent, record: tool)

      expect(bound.execute({ 'arguments' => '{}' })).to eq({ error: 'tool_execution_error' }.to_json)
    end

    it 'reports invalid arguments instead of raising' do
      bound = described_class.new(agent: agent, record: create_http_tool('consultar_estoque'))
      expect(bound.execute({ 'arguments' => 'nao-e-json' })).to eq({ error: 'invalid_tool_arguments' }.to_json)
    end

    it 'runs a native tool with the agent in hand' do
      # Arrange — dublê de nativa, para não acoplar este teste a uma ferramenta concreta
      native = Class.new(Autonomia::Agents::Tools::Native::Base) do
        def self.slug = 'ferramenta_de_teste'
        def self.description = 'teste'
        def call = "conta #{account.id}"
      end
      bound = described_class.new(agent: agent, native: native)

      # Act / Assert
      expect(bound.execute({ 'arguments' => '{}' })).to eq("conta #{account.id}")
    end

    it 'never leaks the message of an unexpected native failure' do
      # Arrange — a nativa carrega credencial; a mensagem pode conter requisição assinada
      native = Class.new(Autonomia::Agents::Tools::Native::Base) do
        def self.slug = 'ferramenta_de_teste'
        def self.description = 'teste'
        def call = raise('X-Amz-Signature=abc senha=segredo')
      end
      bound = described_class.new(agent: agent, native: native)

      # Act
      output = bound.execute({ 'arguments' => '{}' })

      # Assert
      expect(output).to eq({ error: 'tool_execution_error' }.to_json)
      expect(output).not_to include('segredo')
      expect(output).not_to include('X-Amz-Signature')
    end

    it 'truncates a very long output so one tool cannot eat the context' do
      native = Class.new(Autonomia::Agents::Tools::Native::Base) do
        def self.slug = 'ferramenta_de_teste'
        def self.description = 'teste'
        def call = 'a' * 20_000
      end
      output = described_class.new(agent: agent, native: native).execute({ 'arguments' => '{}' })

      expect(output.length).to eq(described_class::MAX_OUTPUT_CHARS)
    end
  end
end
