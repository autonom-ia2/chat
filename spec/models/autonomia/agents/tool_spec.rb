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

  # #1430: a tela ensina a pôr {{cep}} no endereço, e o executor monta o endereço com o valor. O cadastro
  # validava o texto cru, com as chaves, e recusava todo endereço com informação ("Endpoint url inválida").
  describe 'endereço com o que o agente preenche' do
    let(:base) { { account: account, agent: agent, name: 'CEP', slug: 'cep' } }

    it 'aceita {{variável}} no caminho e na query' do
      tool = described_class.new(base.merge(endpoint_url: 'https://viacep.com.br/ws/{{cep}}/json/?f={{ formato }}'))

      expect(tool).to be_valid
    end

    it 'continua recusando o que o executor recusaria, com a variável vazia' do
      tool = described_class.new(base.merge(endpoint_url: 'https://{{host}}/x'))

      expect(tool).not_to be_valid
      expect(tool.errors[:endpoint_url]).to be_present
    end

    it 'recusa modelo que não fecha, com o nome do campo em português' do
      tool = described_class.new(base.merge(endpoint_url: 'https://viacep.com.br/ws/{{cep/json/'))

      I18n.with_locale(:pt_BR) do
        expect(tool).not_to be_valid
        expect(tool.errors.full_messages.join).to eq('Link não é válido')
      end
    end
  end

  # #1430 (revisão adversarial): salvar não roda o modelo. Um `for` sobre uma faixa enorme vira um array de bilhões
  # de números (Liquid `For#render_segment` faz `to_a` na faixa) e derruba o processo. Faixa grande é recusada no
  # endereço, no que vai junto e no recorte da resposta; a pequena continua valendo.
  describe 'repetição sem limite' do
    let(:base) { { account: account, agent: agent, name: 'Faixa', slug: 'faixa' } }
    let(:enorme) { '{% for i in (1..2000000000) %}x{% endfor %}' }

    it 'recusa no endereço sem rodar o modelo' do
      tool = described_class.new(base.merge(endpoint_url: "https://a.test/#{enorme}"))

      inicio = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      expect(tool).not_to be_valid
      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - inicio).to be < 1
      expect(tool.errors[:endpoint_url]).to be_present
    end

    it 'recusa no que vai junto e no recorte da resposta' do
      tool = described_class.new(base.merge(endpoint_url: 'https://a.test/x', http_method: 'POST',
                                            request_body_template: enorme, response_mapping: { 'template' => enorme }))

      expect(tool).not_to be_valid
      expect(tool.errors.attribute_names).to include(:request_body_template, :response_mapping)
    end

    # Revisão adversarial do #1430: o `Host` do cadastro substituía o do endereço e levava a chave guardada a outro site
    # sem passar pela regra de digitar de novo.
    it 'recusa cabeçalho que muda para onde ou como o pedido vai' do
      %w[Host content-length Transfer-Encoding Connection X-Forwarded-Host Forwarded X-Original-URL X-Rewrite-URL].each do |nome|
        tool = described_class.new(base.merge(endpoint_url: 'https://a.test/x', headers_config: [{ key: nome, value: 'b.test', secret: false }]))

        expect(tool).not_to be_valid
        expect(tool.errors[:headers_config]).to be_present
      end
    end

    it 'recusa modelo longo demais no que vai junto, no recorte e na chave de acesso' do
      longo = "{{ q }}#{'x' * Autonomia::Agents::Tool::MAX_MODELO}"
      tool = described_class.new(base.merge(endpoint_url: 'https://a.test/x', http_method: 'POST', request_body_template: longo,
                                            response_mapping: { 'template' => longo },
                                            headers_config: [{ key: 'x-a', value: longo, secret: false }]))

      expect(tool).not_to be_valid
      expect(tool.errors.attribute_names).to include(:request_body_template, :response_mapping, :headers_config)
    end

    it 'recusa mais de 20 cabeçalhos' do
      cabecalhos = Array.new(21) { |i| { key: "x-#{i}", value: 'a', secret: false } }
      tool = described_class.new(base.merge(endpoint_url: 'https://a.test/x', headers_config: cabecalhos))

      expect(tool).not_to be_valid
      expect(tool.errors[:headers_config]).to be_present
    end

    it 'recusa link longo demais sem estourar a pilha' do
      cheio = described_class.new(base.merge(endpoint_url: "https://a.test/#{'{{q}}' * 3000}"))
      parametro = [{ name: 'q', type: 'string', required: true }]
      no_teto = described_class.new(base.merge(endpoint_url: "https://a.test/#{'{{q}}/' * 330}", param_schema: parametro))

      expect(cheio).not_to be_valid
      expect(cheio.errors[:endpoint_url]).to be_present
      expect(no_teto).to be_valid
    end

    it 'recusa faixa grande no valor de uma chave de acesso' do
      tool = described_class.new(base.merge(endpoint_url: 'https://a.test/x',
                                            headers_config: [{ key: 'x-a', value: enorme, secret: false }]))

      expect(tool).not_to be_valid
      expect(tool.errors[:headers_config]).to be_present
    end

    it 'recusa faixa montada com o que o agente preenche' do
      tool = described_class.new(base.merge(endpoint_url: 'https://a.test/x', http_method: 'POST',
                                            request_body_template: '{% for i in (1..n) %}x{% endfor %}'))

      expect(tool).not_to be_valid
    end

    it 'aceita faixa pequena' do
      tool = described_class.new(base.merge(endpoint_url: 'https://a.test/x', http_method: 'POST',
                                            request_body_template: '[{% for i in (1..3) %}{{ i }}{% endfor %}]'))

      expect(tool).to be_valid
    end
  end

  # #1430 (revisão adversarial): quem tem a chave não pode trocar o site e levar a chave guardada junto.
  describe 'segredo guardado e endereço em outro site' do
    let!(:tool) do
      described_class.create!(account: account, agent: agent, name: 'Frete', slug: 'frete', endpoint_url: 'https://api.loja.test/frete',
                              headers_config: [{ key: 'x-api-key', value: 'guardado-123', secret: true }])
    end

    it 'recusa trocar o site mantendo a chave guardada' do
      tool.endpoint_url = 'https://coletor.test/x'

      expect(tool).not_to be_valid
      expect(tool.errors[:headers_config]).to be_present
    end

    it 'aceita trocar o site com a chave digitada de novo' do
      tool.assign_attributes(endpoint_url: 'https://outro.test/x', headers_config: [{ key: 'x-api-key', value: 'nova-456', secret: true }])

      expect(tool).to be_valid
    end

    it 'aceita mudar o caminho no mesmo site' do
      tool.endpoint_url = 'https://api.loja.test/frete/v2?cep={{cep}}'

      expect(tool).to be_valid
    end

    it 'recusa trocar a porta ou o esquema do mesmo host' do
      tool.endpoint_url = 'https://api.loja.test:8443/frete'

      expect(tool).not_to be_valid
    end
  end

  # #1430: a tela mostra cada informação pelo nome de gente ("CEP"). O rótulo fica guardado, mas nunca vai ao
  # modelo: o schema da OpenAI continua só com tipo e descrição.
  describe 'rótulo da informação' do
    let(:tool) do
      described_class.create!(
        account: account, agent: agent, name: 'CEP', slug: 'cep', endpoint_url: 'https://viacep.com.br/ws/{{cep}}/json/',
        param_schema: [{ name: 'cep', type: 'string', description: 'O CEP', required: true, label: '  CEP  ' },
                       { name: 'uf', type: 'string', description: 'Estado', required: true }]
      )
    end

    it 'guarda o rótulo sem espaços e omite quando não veio' do
      expect(tool.param_schema).to eq([
                                        { 'name' => 'cep', 'type' => 'string', 'description' => 'O CEP', 'required' => true,
                                          'label' => 'CEP' },
                                        { 'name' => 'uf', 'type' => 'string', 'description' => 'Estado', 'required' => true }
                                      ])
    end

    it 'não manda o rótulo ao modelo' do
      expect(tool.openai_schema.dig(:parameters, :properties, 'cep')).to eq('type' => 'string', 'description' => 'O CEP')
    end
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
