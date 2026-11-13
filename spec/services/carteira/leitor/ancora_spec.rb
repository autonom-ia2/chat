require 'rails_helper'

# E6 (#2899): o valor que o modelo devolveu só é aceito se estiver escrito nas páginas. Dados fictícios.
RSpec.describe Carteira::Leitor::Ancora do
  subject(:ancora) { described_class.new(texto) }

  let(:texto) do
    <<~TEXTO
      SEGURADORA EXEMPLO S.A.   Apólice nº: EX-2026.001234   Proposta nº: 998877
      Vigência: das 24h de 12/11/2026 às 24h de 12/11/2027. Emissão em 2026-11-10.
      Segurado: José   Antônio  Exemplo    CPF: 123.456.789-00    CNPJ do estipulante: 12.345.678/0001-00
      Prêmio total: R$ 2.254,98 em 6 parcelas. Importância segurada: R$ 80.000
    TEXTO
  end

  it 'texto: aceita o que está escrito, sem contar caixa, acento, espaço e pontuação, e devolve sem espaço sobrando' do
    expect(ancora.escrito('  seguradora   exemplo SA ')).to eq('seguradora exemplo SA')
    expect(ancora.escrito('Jose Antonio Exemplo')).to eq('Jose Antonio Exemplo')
  end

  it 'texto: recusa o que tem palavra fora das páginas, o vazio, só pontuação, o que não é texto e o comprido demais' do
    recusados = ['Seguradora Inventada', 'José Antônio Trocado', '', '   ', '- / .', nil, 123, ['Seguradora Exemplo'],
                 Array.new(60) { 'exemplo' }.join(' ')]

    expect(recusados.map { |valor| ancora.escrito(valor) }).to all(be_nil)
  end

  it 'número da apólice: letras e dígitos juntos e na ordem' do
    expect([ancora.codigo('EX-2026.001234'), ancora.codigo(' ex 2026 001234 ')]).to eq(['EX-2026.001234', 'ex 2026 001234'])
    expect(['EX-2026.001235', '2026.001234-EX', '', '--', nil, 2026].map { |valor| ancora.codigo(valor) }).to all(be_nil)
  end

  it 'documento: só CPF ou CNPJ escrito nas páginas, devolvido só com os dígitos' do
    expect([ancora.documento('123.456.789-00'), ancora.documento('12345678000100')]).to eq(%w[12345678900 12345678000100])
    expect(['123.456.789-01', '123.456.789', '998877', '', nil].map { |valor| ancora.documento(valor) }).to all(be_nil)
  end

  it 'data: AAAA-MM-DD que aparece nas páginas como dia, mês e ano' do
    expect(%w[2026-11-12 2027-11-12 2026-11-10].map { |valor| ancora.data(valor) }).to eq(%w[2026-11-12 2027-11-12 2026-11-10])
    expect(['2027-11-13', '12/11/2026', '2026-13-45', 'ontem', '', nil, 20_261_112].map { |valor| ancora.data(valor) }).to all(be_nil)
  end

  it 'valor: centavos inteiros e positivos que aparecem nas páginas; o redondo também vale sem os centavos' do
    expect([ancora.centavos(225_498), ancora.centavos(8_000_000)]).to eq([225_498, 8_000_000])
    expect([225_499, 0, -225_498, 2254.98, '225498', nil].map { |valor| ancora.centavos(valor) }).to all(be_nil)
  end

  it 'página sem dígito nem letra não confirma nada' do
    vazia = described_class.new(" \n ")

    expect([vazia.escrito('Exemplo'), vazia.codigo('EX-1'), vazia.documento('123.456.789-00'), vazia.data('2026-11-12'),
            vazia.centavos(100)]).to all(be_nil)
  end
end
