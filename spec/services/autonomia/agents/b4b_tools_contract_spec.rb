require 'rails_helper'

RSpec.describe Autonomia::Agents::Answerer, 'B4b tool surface', type: :service do
  let(:account) { create(:account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(
      account: account,
      name: 'Clara',
      agent_type: 'custom',
      instruction: 'Atenda com clareza.',
      config: { 'with_knowledge' => false }
    )
  end
  let(:model_reply) do
    {
      reply: 'Resposta do teste', confidence: 0.9, should_handoff: false, handoff_reason: nil,
      used_snippet_ids: [], answered_from_knowledge: false
    }.to_json
  end

  def stub_model_with_call(call)
    captured = {}
    resolver = instance_double(Crm::Ai::CredentialResolver, resolve: 'ai-credential')
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(resolver)

    client = instance_double(Crm::Ai::ResponsesClient)
    allow(client).to receive(:create_with_tool_executor) do |**kwargs, &executor|
      captured[:tools] = kwargs[:tools]
      captured[:outputs] = executor.call([call])
      { text: model_reply }
    end
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(client)
    captured
  end

  def create_http_tool(http_method: 'POST')
    Autonomia::Agents::Tool.create!(
      account: account,
      agent: agent,
      name: http_method == 'GET' ? 'Consulta segura' : 'Atualiza sistema',
      slug: http_method == 'GET' ? 'consulta_segura' : 'atualiza_sistema',
      endpoint_url: 'https://b4b-local-provider.test/resource',
      http_method: http_method,
      param_schema: []
    )
  end

  def stub_local_provider(body:)
    tempfile = Tempfile.new('b4b-local-provider', binmode: true)
    tempfile.write(body)
    tempfile.rewind
    result = SafeFetch::Result.new(
      tempfile: tempfile, filename: 'response.json', content_type: 'application/json'
    )

    allow(SafeFetch).to receive(:fetch) do |url, **_options, &block|
      expect(url).to eq('https://b4b-local-provider.test/resource')
      block.call(result)
    end
    tempfile
  end

  it 'não faz request HTTP diferente de GET para quem só vê e registra viewer_not_allowed' do
    tool = create_http_tool
    captured = stub_model_with_call('name' => tool.slug, 'call_id' => 'call-1', 'arguments' => '{}')
    expect(SafeFetch).not_to receive(:fetch)

    result = described_class.new(
      agent: agent, query: 'atualize', trust_instruction: true, test_mode: true, pode_editar: false
    ).answer

    expect(captured[:outputs]).to be_present
    expect(result.skipped_tools).to include(
      include(slug: tool.slug, name: tool.name, code: 'viewer_not_allowed')
    )
    expect(result.writes_external).to be(false)
  end

  it 'permite o executor oficial para quem edita e marca writes_external' do
    tool = create_http_tool
    tempfile = stub_local_provider(body: '{"ok":true}')
    stub_model_with_call('name' => tool.slug, 'call_id' => 'call-2', 'arguments' => '{}')

    result = described_class.new(
      agent: agent, query: 'atualize', trust_instruction: true, test_mode: true, pode_editar: true
    ).answer

    expect(result.skipped_tools).to be_empty
    expect(result.writes_external).to be(true)
  ensure
    tempfile&.close!
  end

  it 'mantém GET disponível para quem só vê e não sinaliza escrita externa' do
    tool = create_http_tool(http_method: 'GET')
    tempfile = stub_local_provider(body: '{"items":[] }')
    stub_model_with_call('name' => tool.slug, 'call_id' => 'call-3', 'arguments' => '{}')

    result = described_class.new(
      agent: agent, query: 'consulte', trust_instruction: true, test_mode: true, pode_editar: false
    ).answer

    expect(result.skipped_tools).to be_empty
    expect(result.writes_external).to be(false)
  ensure
    tempfile&.close!
  end

  it 'recusa uma ferramenta assíncrona no Testar sem ToolRun nem job' do
    bound = instance_double(
      Autonomia::Agents::Tools::Bound,
      slug: 'cotar_seguro',
      async?: true,
      openai_schema: {
        type: 'function', name: 'cotar_seguro', description: 'Provider local nomeado',
        parameters: { type: 'object', properties: {}, required: [], additionalProperties: false }, strict: true
      }
    )
    allow(Autonomia::Agents::Tools::Bound).to receive(:for_agent).with(agent).and_return([bound])
    captured = stub_model_with_call('name' => 'cotar_seguro', 'call_id' => 'call-4', 'arguments' => '{}')
    expect(bound).not_to receive(:execute)

    result = nil
    expect do
      result = described_class.new(
        agent: agent, query: 'cote', trust_instruction: true, test_mode: true, pode_editar: true
      ).answer
    end.not_to change(Autonomia::Agents::ToolRun, :count)

    expect(captured[:outputs]).to be_present
    expect(result.skipped_tools).to include(
      include(slug: 'cotar_seguro', code: 'not_in_test')
    )
  end
end
