require 'rails_helper'

# #1444: todo erro de render sobe como `Liquid::Error` — inclusive a exceção que não é do Liquid, que o
# `render!` relançaria crua e escaparia do tratamento da ferramenta.
RSpec.describe Autonomia::Agents::Tools::ModeloLiquid do
  let(:modelo) { described_class.ler('a {{ q }} b', recusa: 'x') }

  # #1430 (revisão adversarial): `for` sobre faixa grande vira um array de bilhões de números antes da primeira volta.
  describe 'faixa grande' do
    it 'tells the dangerous ranges apart from the small ones' do
      expect(described_class.faixa_grande?('{% for i in (1..2000000000) %}x{% endfor %}')).to be(true)
      expect(described_class.faixa_grande?('{% for i in (1..n) %}x{% endfor %}')).to be(true)
      expect(described_class.faixa_grande?('{% if a %}{% for i in (1..5000) %}{% endfor %}{% endif %}')).to be(true)
      expect(described_class.faixa_grande?('{% for i in (1..3) %}x{% endfor %}')).to be(false)
      expect(described_class.faixa_grande?('{% for i in response.itens %}x{% endfor %}')).to be(false)
      expect(described_class.faixa_grande?('{% for i in (1..2 %}')).to be(false)
    end

    # Tester do #1430: a faixa guardada num `assign` (ou passada a um filtro) também vira lista inteira, e a repetição
    # sem nada dentro não soma no limite de render (5 milhões de voltas em segundos).
    it 'finds the range anywhere in the template, and refuses a loop with nothing inside' do
      expect(described_class.faixa_grande?('{% assign r = (1..2000000000) %}{% for i in r %}x{% endfor %}')).to be(true)
      expect(described_class.faixa_grande?('{{ (1..2000000000) | join }}')).to be(true)
      expect(described_class.faixa_grande?('{% if (1..n) contains 3 %}x{% endif %}')).to be(true)
    end

    it 'refuses a loop with nothing inside, which the render limit does not count' do
      expect(described_class.faixa_grande?('{% for a in (1..1000) %}{% for b in (1..1000) %}{% endfor %}{% endfor %}')).to be(true)
      expect(described_class.faixa_grande?('{% for a in response.itens %} {% endfor %}')).to be(true)
      expect(described_class.faixa_grande?('{% tablerow a in response.itens %}{% endtablerow %}')).to be(true)
      expect(described_class.faixa_grande?('{% tablerow a in response.itens %}{{ a }}{% endtablerow %}')).to be(false)
      expect(described_class.faixa_grande?('{% for a in response.itens %}{% else %}nada{% endfor %}')).to be(true)
      expect(described_class.faixa_grande?('{% assign r = (1..10) %}{% for i in r %}{{ i }}{% endfor %}')).to be(false)
    end

    # Revisão adversarial do #1430: os limites do Liquid conferem entre nós, e a cadeia de filtros de um {{ }} roda
    # inteira antes — `replace` multiplicava o texto por 10 a cada filtro (100 MB num nó) e `split | sort | join` em
    # cadeia passava do prazo. Agora cada filtro confere o prazo antes e o tamanho do que devolve.
    it 'stops a filter chain that grows or takes too long inside one {{ }}' do
      dez = '"aaaaaaaaaa"'
      cresce = "{{ \"a\" #{Array.new(7) { "| replace: \"a\", #{dez} " }.join}| size }}"
      cola = "{{ \"#{Array.new(2000, 'a').join(',')}\" | split: \",\" | join: \"#{'x' * 1000}\" | size }}"

      [cresce, cola].each do |texto|
        expect { described_class.renderizar(described_class.ler(texto, recusa: 'x'), {}, nil) }.to raise_error(Liquid::MemoryError)
      end
    end

    # Revisão adversarial (2ª): uma lista com o mesmo texto grande repetido (`concat`) passava com poucos itens.
    it 'weighs a list by the text inside it, not only by how many items it has' do
      grande = "{% assign x = q | split: \"#\" %}{{ x #{Array.new(10, '| concat: x').join(' ')} | size }}"

      # Pelo caminho do cabeçalho, que aceita `assign`.
      modelo = described_class.conferir_faixas!(Liquid::Template.parse(grande, error_mode: :strict))

      expect { described_class.renderizar(modelo, { 'q' => 'a' * 200_000 }, nil) }.to raise_error(Liquid::MemoryError)
    end

    # Revisão adversarial (3ª): cada render ganhava um segundo, e uma chamada faz um render por cabeçalho. Dentro da
    # chamada (`com_orcamento`) os renders dividem o mesmo prazo; o tempo de rede não entra, só o de render (`medir`).
    it 'shares one deadline among all renders of a call' do
      stub_const('Autonomia::Agents::Tools::ModeloLiquid::PRAZO', 0.05)
      modelo = described_class.ler('{{ q }}', recusa: 'x')

      described_class.com_orcamento do
        described_class.medir { sleep 0.06 }
        expect { described_class.renderizar(modelo, { 'q' => 'a' }, nil) }.to raise_error(Liquid::MemoryError)
      end
      expect(described_class.renderizar(modelo, { 'q' => 'a' }, nil)).to eq('a')
    end

    it 'checks the deadline before each filter' do
      stub_const('Autonomia::Agents::Tools::ModeloLiquid::PRAZO', 0.05)
      ordena = Array.new(40, '| split: "" | sort | join: ""').join(' ')
      texto = "{{ q #{ordena} | size }}"

      expect { described_class.renderizar(described_class.ler(texto, recusa: 'x'), { 'q' => 'zyx' * 20_000 }, nil) }
        .to raise_error(Liquid::MemoryError)
    end

    it 'keeps everyday filters working' do
      texto = '{{ q | replace: "-", "" }} {{ itens | join: ", " }}'
      saida = described_class.renderizar(described_class.ler(texto, recusa: 'x'), { 'q' => '01001-000', 'itens' => %w[a b] }, nil)

      expect(saida).to eq('01001000 a, b')
    end

    it 'counts tablerow like for' do
      expect(described_class.faixa_grande?('{% tablerow i in (1..2000000000) %}x{% endtablerow %}')).to be(true)
    end

    it 'refuses it when reading the template' do
      expect { described_class.ler('{% for i in (1..2000000000) %}x{% endfor %}', recusa: 'x') }
        .to raise_error(Autonomia::Agents::Tools::HttpExecutor::ValorRecusado, 'faixa_grande')
    end
  end

  it 'raises the Liquid error of a missing variable' do
    expect { described_class.renderizar(modelo, {}, nil) }.to raise_error(Liquid::UndefinedVariable)
  end

  it 'turns an error that is not from Liquid into Liquid::InternalError' do
    filtro = ->(_valor) { raise ArgumentError, 'valor com segredo-123' }

    allow(Rails.logger).to receive(:warn)

    expect { described_class.renderizar(modelo, { 'q' => 'x' }, filtro) }
      .to raise_error(Liquid::InternalError) { |erro|
        expect(erro.message).not_to include('segredo-123')
        expect(erro.cause).to be_nil
      }
    expect(Rails.logger).to have_received(:warn).with(include('original=ArgumentError'))
    expect(Rails.logger).not_to have_received(:warn).with(include('segredo-123'))
  end
end
