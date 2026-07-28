require 'rails_helper'

RSpec.describe Autonomia::Agents::Tool do
  let(:account) { create(:account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(
      account: account, name: 'Bot', agent_type: 'custom', status: :active,
      enabled: true, instruction: 'Atenda.'
    )
  end

  it 'builds a strict OpenAI function schema from params' do
    tool = described_class.create!(
      account: account,
      agent: agent,
      name: 'Consulta de estoque',
      slug: 'consultar_estoque',
      description: 'Consulta estoque por termo.',
      endpoint_url: 'https://giraautopecas.api-autonomia.com/stock/search',
      param_schema: [{ name: 'q', type: 'string', description: 'Busca', required: true }]
    )

    expect(tool.openai_schema).to include(type: 'function', name: 'consultar_estoque', strict: true)
    expect(tool.openai_schema.dig(:parameters, :required)).to eq(['q'])
    expect(tool.openai_schema.dig(:parameters, :additionalProperties)).to be(false)
  end

  it 'masks secret header values in serialized output' do
    tool = described_class.create!(
      account: account,
      agent: agent,
      name: 'Consulta',
      slug: 'consultar',
      endpoint_url: 'https://example.com/search',
      headers_config: [{ key: 'x-api-key', value: 'secret-token', secret: true }]
    )

    expect(tool.masked_headers_config.first['value']).to eq(described_class.masked_header_value)
  end

  it 'rejects unsafe endpoints' do
    tool = described_class.new(
      account: account,
      agent: agent,
      name: 'Unsafe',
      slug: 'unsafe',
      endpoint_url: 'http://localhost:3000'
    )

    expect(tool).not_to be_valid
    expect(tool.errors[:endpoint_url]).to be_present
  end
end
