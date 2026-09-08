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

  # O MESMO DEFEITO QUE DEIXOU UM AGENTE MUDO EM PRODUÇÃO, por outro caminho.
  #
  # Em 08/09/2026 uma ferramenta NATIVA com um parâmetro opcional derrubou a chamada inteira à
  # OpenAI: em `strict: true` toda chave de `properties` precisa estar em `required`. As ferramentas
  # HTTP montam o schema aqui, com a mesma regra — e o risco é maior, porque o parâmetro vem do que
  # a corretora cadastrou na tela, não de código nosso. Basta alguém desmarcar "obrigatório".
  describe 'parâmetro opcional no schema strict' do
    def ferramenta_com(params)
      described_class.create!(
        account: account, agent: agent, name: 'Consulta', slug: "consulta_#{SecureRandom.hex(3)}",
        description: 'Consulta algo.', endpoint_url: 'https://exemplo.test/x', param_schema: params
      )
    end

    it 'lista todo parametro em required, inclusive o opcional' do
      # Arrange
      tool = ferramenta_com([{ name: 'q', type: 'string', description: 'Busca', required: true },
                             { name: 'pagina', type: 'integer', description: 'Página', required: false }])

      # Act
      schema = tool.openai_schema

      # Assert
      expect(schema[:parameters][:required]).to match_array(%w[q pagina])
    end

    it 'diz que e opcional pelo tipo aceitar null' do
      tool = ferramenta_com([{ name: 'q', type: 'string', description: 'Busca', required: true },
                             { name: 'pagina', type: 'integer', description: 'Página', required: false }])
      props = tool.openai_schema[:parameters][:properties]

      expect(props['pagina']['type']).to match_array(%w[integer null])
      expect(props['q']['type']).to eq('string')
    end

    # A garantia que a OpenAI cobra, dita como ela cobra: nenhuma chave de properties fora de
    # required. Vale para qualquer combinação que a corretora cadastre.
    it 'nunca deixa chave de properties fora de required' do
      tool = ferramenta_com([{ name: 'a', type: 'string', description: 'A', required: false },
                             { name: 'b', type: 'string', description: 'B', required: false },
                             { name: 'c', type: 'boolean', description: 'C', required: true }])
      schema = tool.openai_schema

      expect(schema[:parameters][:required]).to match_array(schema[:parameters][:properties].keys)
    end
  end
end
