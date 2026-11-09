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
  # Número que se eleva ao quadrado a cada volta dobra de tamanho por volta: não escreve nada nem conta no `assign`.
  # 26 voltas bastam para provar a recusa sem pesar quando o limite falta.
  let(:quadrado) do
    '{% assign n = 3 %}{% for i in (1..26) %}{% assign n = n | times: n %}{% endfor %}{{ n | size }}'
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

  # #1430 (revisão adversarial): ferramenta antiga gravada com faixa grande é recusada antes de montar o pedido.
  it 'refuses a huge range in the address, the body or the mapping without running it' do
    enorme = '{% for i in (1..2000000000) %}x{% endfor %}'
    allow(SafeFetch).to receive(:fetch)
    [{ endpoint_url: "https://a.test/#{enorme}" }, { request_body_template: enorme },
     { response_mapping: { 'template' => enorme } }].each do |campo|
      legado = tool.dup.tap { |copia| copia.slug = "legado_#{SecureRandom.hex(3)}" }
      legado.save!
      legado.update_columns(campo) # rubocop:disable Rails/SkipsModelValidations

      inicio = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      expect { described_class.new(tool: legado.reload, params: { q: 'freio' }).call }
        .to raise_error(described_class::Error, /faixa_grande/)
      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - inicio).to be < 1
    end
    expect(SafeFetch).not_to have_received(:fetch)
  end

  # #1430 (revisão do delta): sem faixa grande, o modelo ainda pode crescer — texto que dobra a cada volta, `for`
  # aninhados. Todo render da ferramenta tem limite de recursos e para cedo, sem enviar nada.
  it 'stops a template that grows without a big range, in a header, the body or the mapping' do
    dobra = '{% assign s = "x" %}{% for i in (1..80) %}{% assign s = s | append: s %}{% endfor %}{{ s | size }}'
    aninhado = '{% for a in (1..1000) %}{% for b in (1..1000) %}{% for c in (1..1000) %}x{% endfor %}{% endfor %}{% endfor %}'
    allow(SafeFetch).to receive(:fetch)
    [{ headers_config: [{ 'key' => 'x-a', 'value' => dobra, 'secret' => false }] },
     { headers_config: [{ 'key' => 'x-a', 'value' => quadrado, 'secret' => false }] },
     { request_body_template: aninhado }].each do |campo|
      legado = tool.dup.tap { |copia| copia.slug = "legado_#{SecureRandom.hex(3)}" }
      legado.save!
      legado.update_columns(campo) # rubocop:disable Rails/SkipsModelValidations

      inicio = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      expect { described_class.new(tool: legado.reload, params: { q: 'freio' }).call }.to raise_error(described_class::Error)
      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - inicio).to be < 2
    end
    expect(SafeFetch).not_to have_received(:fetch)
  end

  it 'stops a mapping that grows, without handing the agent a piece of it' do
    tempfile = Tempfile.new('tool-response')
    tempfile.write('{"ok":true}')
    tempfile.rewind
    resultado = SafeFetch::Result.new(tempfile: tempfile, filename: 'r.json', content_type: 'application/json')
    allow(SafeFetch).to receive(:fetch).and_yield(resultado)
    aninhado = '{% for a in (1..1000) %}{% for b in (1..1000) %}{% for c in (1..1000) %}x{% endfor %}{% endfor %}{% endfor %}'
    [aninhado, quadrado].each do |modelo|
      tool.update_columns(response_mapping: { 'template' => modelo }) # rubocop:disable Rails/SkipsModelValidations

      inicio = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      expect { described_class.new(tool: tool.reload, params: { q: 'freio' }).call }
        .to raise_error(described_class::Error, /limite_do_modelo/)
      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - inicio).to be < 2
      tempfile.rewind
    end
  ensure
    tempfile&.close!
  end

  # Tester do #1430 (B11): filtro caro repetido (split de um texto grande a cada volta) não soma nos limites de nós,
  # e 300 voltas eram 5 s de CPU. Todo render tem prazo; aqui o prazo é encurtado para o teste não pesar.
  it 'stops a template that takes too long, in a header and in the mapping' do
    stub_const('Autonomia::Agents::Tools::ModeloLiquid::PRAZO', 0.05)
    lento = '{% assign s = "x" %}{% for i in (1..14) %}{% assign s = s | append: s %}{% endfor %}' \
            '{% for i in (1..300) %}{{ s | split: "" | size }}{% endfor %}'
    tempfile = Tempfile.new('tool-response')
    tempfile.write('{"ok":true}')
    tempfile.rewind
    resultado = SafeFetch::Result.new(tempfile: tempfile, filename: 'r.json', content_type: 'application/json')
    allow(SafeFetch).to receive(:fetch).and_yield(resultado)

    tool.update_columns(headers_config: [{ 'key' => 'x-a', 'value' => lento, 'secret' => false }]) # rubocop:disable Rails/SkipsModelValidations
    expect { described_class.new(tool: tool.reload, params: { q: 'freio' }).call }.to raise_error(described_class::Error)
    expect(SafeFetch).not_to have_received(:fetch)

    tool.update_columns(headers_config: [], response_mapping: { 'template' => lento }) # rubocop:disable Rails/SkipsModelValidations
    expect { described_class.new(tool: tool.reload, params: { q: 'freio' }).call }
      .to raise_error(described_class::Error, /limite_do_modelo/)
  ensure
    tempfile&.close!
  end

  it 'gives the whole call one render budget' do
    allow(Autonomia::Agents::Tools::ModeloLiquid).to receive(:com_orcamento).and_call_original
    allow(SafeFetch).to receive(:fetch).and_raise(SafeFetch::FetchError, 'x')

    expect { described_class.new(tool: tool, params: { q: 'freio' }).call }.to raise_error(described_class::Error)
    expect(Autonomia::Agents::Tools::ModeloLiquid).to have_received(:com_orcamento).once
  end

  it 'keeps everyday arithmetic in the mapping' do
    tempfile = Tempfile.new('tool-response')
    tempfile.write('{"preco":89.9,"qtd":3}')
    tempfile.rewind
    resultado = SafeFetch::Result.new(tempfile: tempfile, filename: 'r.json', content_type: 'application/json')
    allow(SafeFetch).to receive(:fetch).and_yield(resultado)
    tool.update!(response_mapping: { 'template' => '{{ response.preco | times: response.qtd }} {{ 1000000 | times: 1000000 }}' })

    expect(described_class.new(tool: tool, params: { q: 'freio' }).call).to eq('269.7 1000000000000')
  ensure
    tempfile&.close!
  end

  it 'keeps a mapping over a normal list working under the limits' do
    tempfile = Tempfile.new('tool-response')
    tempfile.write({ itens: Array.new(500) { |i| { nome: "P#{i}" } } }.to_json)
    tempfile.rewind
    resultado = SafeFetch::Result.new(tempfile: tempfile, filename: 'r.json', content_type: 'application/json')
    allow(SafeFetch).to receive(:fetch).and_yield(resultado)
    tool.update!(response_mapping: { 'template' => '{% for i in response.itens %}{{ i.nome }};{% endfor %}' })

    saida = described_class.new(tool: tool, params: { q: 'freio' }).call

    expect(saida).to start_with('P0;P1;')
    expect(saida).to include('P499;')
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
