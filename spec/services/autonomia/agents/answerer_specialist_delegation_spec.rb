require 'rails_helper'

# Delegação do agente PRINCIPAL para um subagente especializado (#311).
# NÃO confundir com handoff para pessoa: esse continua sendo o do CRM (Crm::Ai::HandoffExecutor),
# acionado pela instrução. Aqui ninguém é atribuído e a conversa não sai do bot.
RSpec.describe Autonomia::Agents::Answerer do
  let(:account) { create(:account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(
      account: account, name: 'Bot', agent_type: 'custom', status: :active, enabled: true,
      instruction: 'Atenda o cliente.', config: { 'with_knowledge' => false }
    )
  end
  let(:model_reply) do
    { reply: 'Sua cotação saiu.', confidence: 0.9, should_handoff: false, handoff_reason: nil,
      used_snippet_ids: [], answered_from_knowledge: false }.to_json
  end

  # Captura o que o PRINCIPAL recebeu como ferramentas e, opcionalmente, dispara uma chamada de
  # função para exercitar o roteamento.
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

  def create_tool(slug)
    Autonomia::Agents::Tool.create!(
      account: account, agent: agent, name: slug.humanize, slug: slug,
      endpoint_url: "https://adapters.example.com/#{slug}", param_schema: []
    )
  end

  def create_specialist(tool_slugs: [])
    Autonomia::Agents::Specialist.create!(
      agent: agent, name: 'Especialista de Automóvel', slug: 'auto',
      description: 'cotação de seguro de automóvel', instruction: 'Você cota automóvel.',
      tool_slugs: tool_slugs
    )
  end

  it 'offers the specialist to the main agent as a function' do
    # Arrange
    create_specialist
    captured = stub_main_agent

    # Act
    result = described_class.new(agent: agent, query: 'quero cotar um carro',
                                 trust_instruction: true).answer

    # Assert
    expect(result.reply).to eq('Sua cotação saiu.')
    expect(captured[:tools].filter_map { |tool| tool[:name] }).to include('consultar_auto')
  end

  it 'HIDES the tools reserved by the specialist from the main agent' do
    # Arrange — duas ferramentas: uma reservada ao especialista, outra livre
    create_tool('cotar_auto')
    create_tool('consultar_faq')
    create_specialist(tool_slugs: ['cotar_auto'])
    captured = stub_main_agent

    # Act
    described_class.new(agent: agent, query: 'oi', trust_instruction: true).answer

    # Assert — o principal vê a livre e o especialista, nunca a ferramenta de cotação
    names = captured[:tools].filter_map { |tool| tool[:name] }
    expect(names).to contain_exactly('consultar_faq', 'consultar_auto')
    expect(names).not_to include('cotar_auto')
  end

  it 'routes a call to the specialist and returns its prose as the function output' do
    # Arrange
    create_specialist
    runner = instance_double(Autonomia::Agents::Specialists::Runner, call: 'Melhor opção: Porto, R$ 1.200.')
    allow(Autonomia::Agents::Specialists::Runner).to receive(:new).and_return(runner)
    captured = stub_main_agent(
      function_call: { 'name' => 'consultar_auto', 'call_id' => 'call_1',
                       'arguments' => { 'pedido' => 'cotar para o CPF X' }.to_json }
    )

    # Act
    described_class.new(agent: agent, query: 'quero cotar', trust_instruction: true).answer

    # Assert
    expect(Autonomia::Agents::Specialists::Runner).to have_received(:new)
      .with(specialist: instance_of(Autonomia::Agents::Specialist), request: 'cotar para o CPF X')
    expect(captured[:outputs]).to eq(
      [{ type: 'function_call_output', call_id: 'call_1', output: 'Melhor opção: Porto, R$ 1.200.' }]
    )
  end

  it 'reports invalid arguments instead of raising' do
    create_specialist
    captured = stub_main_agent(
      function_call: { 'name' => 'consultar_auto', 'call_id' => 'call_1', 'arguments' => 'nao-e-json' }
    )

    described_class.new(agent: agent, query: 'x', trust_instruction: true).answer

    expect(captured[:outputs].first[:output]).to eq({ error: 'invalid_tool_arguments' }.to_json)
  end

  it 'ignores a disabled specialist entirely' do
    create_tool('cotar_auto')
    create_specialist(tool_slugs: ['cotar_auto']).update!(enabled: false)
    captured = stub_main_agent

    described_class.new(agent: agent, query: 'oi', trust_instruction: true).answer

    # Sem especialista habilitado, a ferramenta volta a ser do principal — sem reserva órfã.
    names = captured[:tools].filter_map { |tool| tool[:name] }
    expect(names).to contain_exactly('cotar_auto')
  end

  it 'behaves exactly as before for an agent with no specialists' do
    create_tool('consultar_faq')
    captured = stub_main_agent

    result = described_class.new(agent: agent, query: 'oi', trust_instruction: true).answer

    expect(result.reply).to eq('Sua cotação saiu.')
    expect(captured[:tools].filter_map { |tool| tool[:name] }).to eq(['consultar_faq'])
  end
end
