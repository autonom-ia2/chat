require 'rails_helper'

# Ferramenta nativa chegando ao turno do agente (#312).
RSpec.describe Autonomia::Agents::Answerer do
  let(:account) { create(:account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(
      account: account, name: 'Bot', agent_type: 'custom', status: :active, enabled: true,
      instruction: 'Atenda o cliente.', config: { 'with_knowledge' => false }
    )
  end
  let(:native) { Autonomia::Agents::Tools::Native::InsuranceCapabilities }
  let(:model_reply) do
    { reply: 'Cotamos auto e vida.', confidence: 0.9, should_handoff: false, handoff_reason: nil,
      used_snippet_ids: [], answered_from_knowledge: false }.to_json
  end

  def stub_main_agent(function_call: nil)
    captured = { tools: nil, outputs: nil }
    resolver = instance_double(Crm::Ai::CredentialResolver, resolve: 'ai-credential')
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(resolver)
    client = instance_double(Crm::Ai::ResponsesClient)
    allow(client).to receive(:create_with_tool_executor) do |**kwargs, &executor|
      captured[:tools] = Array(kwargs[:tools])
      captured[:outputs] = executor.call([function_call]) if function_call && executor
      { text: model_reply }
    end
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(client)
    captured
  end

  def turn_native_on
    agent.update!(config: agent.config.merge('native_tool_slugs' => [native.slug]))
    allow(native).to receive(:available_for?).and_return(true)
  end

  it 'offers an enabled native tool to the agent' do
    turn_native_on
    captured = stub_main_agent

    described_class.new(agent: agent, query: 'o que vocês vendem?', trust_instruction: true).answer

    expect(captured[:tools].filter_map { |tool| tool[:name] }).to include('consultar_produtos_cotacao')
  end

  it 'does not offer a native tool the agent never turned on' do
    captured = stub_main_agent

    described_class.new(agent: agent, query: 'oi', trust_instruction: true).answer

    expect(captured[:tools].filter_map { |tool| tool[:name] }).not_to include('consultar_produtos_cotacao')
  end

  it 'executes the native tool and hands its text back to the model' do
    # Arrange
    turn_native_on
    instance = instance_double(native, call: 'Esta corretora cota hoje: Auto (18 seguradoras).')
    allow(native).to receive(:new).and_return(instance)
    captured = stub_main_agent(
      function_call: { 'name' => 'consultar_produtos_cotacao', 'call_id' => 'c1', 'arguments' => '{}' }
    )

    # Act
    described_class.new(agent: agent, query: 'vocês vendem auto?', trust_instruction: true).answer

    # Assert
    expect(captured[:outputs]).to eq(
      [{ type: 'function_call_output', call_id: 'c1',
         output: 'Esta corretora cota hoje: Auto (18 seguradoras).' }]
    )
  end

  it 'lets a specialist reserve a native tool, hiding it from the main agent' do
    # Arrange
    turn_native_on
    Autonomia::Agents::Specialist.create!(
      agent: agent, name: 'Especialista de Automóvel', slug: 'auto',
      description: 'cotação de automóvel', instruction: 'Você cota automóvel.',
      tool_slugs: [native.slug]
    )
    captured = stub_main_agent

    # Act
    described_class.new(agent: agent, query: 'oi', trust_instruction: true).answer

    # Assert — o principal vê o especialista, não a ferramenta que ele reservou
    names = captured[:tools].filter_map { |tool| tool[:name] }
    expect(names).to include('consultar_auto')
    expect(names).not_to include('consultar_produtos_cotacao')
  end
end
