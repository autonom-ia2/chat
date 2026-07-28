require 'rails_helper'

RSpec.describe Autonomia::Agents::Tools::HttpExecutor do
  let(:account) { create(:account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(
      account: account, name: 'Bot', agent_type: 'custom', status: :active,
      enabled: true, instruction: 'Atenda.'
    )
  end
  let(:tool) do
    Autonomia::Agents::Tool.create!(
      account: account,
      agent: agent,
      name: 'Consulta de estoque',
      slug: 'consultar_estoque',
      endpoint_url: 'https://giraautopecas.api-autonomia.com/clients/gira-autopecas/stock/search',
      headers_config: [
        { key: 'content-type', value: 'application/json', secret: false },
        { key: 'x-api-key', value: 'token-secreto', secret: true }
      ],
      request_body_template: '{"q":"{{q}}","limit":5}',
      param_schema: [{ name: 'q', type: 'string', description: 'Busca', required: true }]
    )
  end

  it 'executes a templated POST with configured headers' do
    tempfile = Tempfile.new('tool-response')
    tempfile.write({ items: [{ name: 'Pastilha Titan' }] }.to_json)
    tempfile.rewind
    result = SafeFetch::Result.new(tempfile: tempfile, filename: 'response.json', content_type: 'application/json')

    expect(SafeFetch).to receive(:fetch).with(
      tool.endpoint_url,
      hash_including(
        method: :post,
        body: '{"q":"freio dianteiro titan","limit":5}',
        headers: hash_including('x-api-key' => 'token-secreto', 'content-type' => 'application/json'),
        validate_content_type: false
      )
    ).and_yield(result)

    output = described_class.new(tool: tool, params: { q: 'freio dianteiro titan' }).call
    expect(JSON.parse(output).dig('items', 0, 'name')).to eq('Pastilha Titan')
  ensure
    tempfile&.close!
  end

  it 'raises a compact execution error without leaking secrets' do
    allow(SafeFetch).to receive(:fetch).and_raise(SafeFetch::FetchError, 'token-secreto failed')

    expect do
      described_class.new(tool: tool, params: { q: 'freio' }).call
    end.to raise_error(described_class::Error, /tool_execution_error/)
  end
end
