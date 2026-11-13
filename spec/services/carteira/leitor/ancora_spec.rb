require 'rails_helper'

# E6 (#2899): o valor que o modelo devolveu só é aceito se estiver escrito, inteiro, numa das páginas. Dados fictícios.
RSpec.describe Carteira::Leitor::Ancora do
  subject(:ancora) { described_class.new([pagina.new(numero: 1, texto: primeira), pagina.new(numero: 2, texto: segunda)]) }

  let(:pagina) { Carteira::Leitor::Paginas::Pagina }
  let(:primeira) do
    <<~TEXTO
      SEGURADORA EXEMPLO S.A.   Apólice nº: EX-2026.001234   Proposta nº: 998877
      Vigência: das 24h de 12/11/2026 às 24h de 12/11/2027. Emissão em 2026-11-10.
      Segurado: José   Antônio  Exemplo    CPF: 123.456.789-00    CNPJ do estipulante: 12.345.678/0001-00
      Prêmio líquido: R$ 2.100,00   IOF: R$ 154,98   Prêmio total: R$ 2.254,98 em 6 parcelas de R$ 375,83.
      Importância segurada: R$ 80.000   Produto: Banana Prata Residencial
    TEXTO
  end
  let(:segunda) do
    <<~TEXTO
      Endosso da apólice 0531 12 345678.
      Segurada adicional: Lia
      Maria Modelo. Franquia: R$ 3.500,00
      Item 12/34. CEP 01122-028. Protocolo 15032026. Emitida em 05-01-2027, 06.01.2027 e 07/01/27.
      Juros de 7,38% ao mês. Peso da carga: 1.250,50 kg. Total sem o cifrão: 9.876,54
    TEXTO
  end

  it 'texto: aceita o que está escrito, sem contar caixa, acento, espaço e pontuação, e devolve sem espaço sobrando' do
    expect(ancora.escrito('  seguradora   exemplo s.a. ')).to eq('seguradora exemplo s.a.')
    expect(ancora.escrito('Jose Antonio Exemplo')).to eq('Jose Antonio Exemplo')
    expect(ancora.escrito('Lia Maria Modelo')).to eq('Lia Maria Modelo')
  end

  it 'texto: recusa o que tem palavra fora das páginas, o vazio, só pontuação, o que não é texto e o comprido demais' do
    recusados = ['Seguradora Inventada', 'José Antônio Trocado', '', '   ', '- / .', nil, 123, ['Seguradora Exemplo'],
                 Array.new(60) { 'exemplo' }.join(' ')]

    expect(recusados.map { |valor| ancora.escrito(valor) }).to all(be_nil)
  end

  # Achado C da revisão: "Ana" passava por estar dentro de "Banana", e a frase passava com um pedaço de cada lugar.
  it 'texto: palavra inteira, nunca um pedaço de outra, e a frase seguida, na ordem e na mesma página' do
    expect(ancora.escrito('Banana Prata')).to eq('Banana Prata')
    pedaco_de_palavra = %w[Ana Segura Resid]
    fora_de_ordem_ou_salteada = ['Exemplo José Antônio', 'José Exemplo', 'Seguradora S.A.']
    um_pedaco_de_cada_pagina = ['Banana Prata Residencial Endosso', 'Maria Modelo José Antônio']

    expect((pedaco_de_palavra + fora_de_ordem_ou_salteada + um_pedaco_de_cada_pagina).map { |valor| ancora.escrito(valor) }).to all(be_nil)
  end

  # Achado A da revisão: "001234" passava por estar dentro de "EX-2026.001234".
  it 'número da apólice: o bloco inteiro como está escrito, nunca um pedaço dele' do
    expect([' ex-2026.001234 ', '0531 12 345678', '12/34'].map { |valor| ancora.codigo(valor) })
      .to eq(['ex-2026.001234', '0531 12 345678', '12/34'])
    pedacos = ['001234', '2026.001234', 'EX-2026', 'EX-2026.00123', 'X-2026.001234', '0531 12 3456']
    outros = ['EX-2026.001235', 'ex 2026 001234', '2026.001234-EX', '', '--', '%', nil, 2026]

    expect((pedacos + outros).map { |valor| ancora.codigo(valor) }).to all(be_nil)
  end

  # Segunda revisão: "1234" passava por "12/34", porque a comparação tirava a pontuação de dentro do bloco.
  it 'número da apólice: a pontuação de dentro conta' do
    expect(['1234', 'ex2026001234', 'EX 2026.001234', '12-34', '053112345678'].map { |valor| ancora.codigo(valor) }).to all(be_nil)
  end

  it 'documento: só CPF ou CNPJ escrito por inteiro nas páginas, devolvido só com os dígitos' do
    expect([ancora.documento('123.456.789-00'), ancora.documento('12345678000100')]).to eq(%w[12345678900 12345678000100])
    # '890.012.345-67' são os últimos dígitos do CPF emendados nos primeiros do CNPJ: não é um documento escrito.
    expect(['123.456.789-01', '123.456.789', '998877', '890.012.345-67', '', nil].map { |valor| ancora.documento(valor) }).to all(be_nil)
  end

  # Segunda revisão, alto 1: o CEP "01122-028" fazia a data 01/12/2028 passar, e o protocolo 15032026, a 15/03/2026.
  it 'data: dígitos colados nunca são data, nem com hífen de CEP' do
    expect(%w[2028-12-01 2026-03-15 0112-20-28].map { |valor| ancora.data(valor) }).to all(be_nil)
  end

  it 'data: aceita cada forma escrita com separador, com o ano curto só depois de barra' do
    expect(%w[2027-01-05 2027-01-06 2027-01-07].map { |valor| ancora.data(valor) }).to eq(%w[2027-01-05 2027-01-06 2027-01-07])
  end

  it 'data: AAAA-MM-DD escrita por inteiro nas páginas como dia, mês e ano' do
    expect(%w[2026-11-12 2027-11-12 2026-11-10].map { |valor| ancora.data(valor) }).to eq(%w[2026-11-12 2027-11-12 2026-11-10])
    # 12/11/20 é só o começo de 12/11/2026.
    expect(['2027-11-13', '2020-11-12', '12/11/2026', '2026-13-45', 'ontem', '', nil, 20_261_112].map { |valor| ancora.data(valor) })
      .to all(be_nil)
  end

  # Achado B da revisão: 2254 passava por estar dentro de "2.254,98".
  it 'valor: um dos valores em dinheiro escritos, por inteiro; um pedaço dele e o valor sem os centavos não passam' do
    expect([225_498, 210_000, 350_000].map { |valor| ancora.centavos(valor) }).to eq([225_498, 210_000, 350_000])
    pedacos = [2254, 22_549, 25_498, 254, 98, 6]
    outros = [225_499, 8_000_000, 80_000, 0, -225_498, 2254.98, '225498', nil]

    expect((pedacos + outros).map { |valor| ancora.centavos(valor) }).to all(be_nil)
  end

  # Segunda revisão, alto 2.
  it 'valor: porcentagem nunca é dinheiro, e só o que vem logo depois de "R$" tem o cifrão' do
    expect([ancora.centavos(738), ancora.com_cifrao?(738)]).to eq([nil, false])
    expect([125_050, 987_654].map { |valor| [ancora.centavos(valor), ancora.com_cifrao?(valor)] }).to eq([[125_050, false], [987_654, false]])
    expect([225_498, 350_000].map { |valor| ancora.com_cifrao?(valor) }).to eq([true, true])
  end

  # O limite que fica: a âncora só diz que o valor está escrito, não que ele é o prêmio total. Quem mede se o modelo
  # troca o prêmio pela parcela ou pelo IOF é a bateria com gabarito.
  it 'valor: a parcela e o IOF também estão escritos, e a âncora não sabe que não são o prêmio' do
    expect([ancora.centavos(37_583), ancora.centavos(15_498)]).to eq([37_583, 15_498])
  end

  it 'página sem dígito nem letra não confirma nada' do
    vazia = described_class.new([pagina.new(numero: 1, texto: " \n ")])

    expect([vazia.escrito('Exemplo'), vazia.codigo('EX-1'), vazia.documento('123.456.789-00'), vazia.data('2026-11-12'),
            vazia.centavos(100)]).to all(be_nil)
  end
end
