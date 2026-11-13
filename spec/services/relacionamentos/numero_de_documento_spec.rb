require 'rails_helper'

# Épico #1240, decisão R1: o CPF e o CNPJ como número. Todos os números daqui são inventados (sequências), válidos só na
# conta do dígito verificador; o CNPJ com letras é o exemplo público da Receita para o formato novo.
RSpec.describe Relacionamentos::NumeroDeDocumento do
  def numero(texto)
    described_class.new(texto)
  end

  it 'reconhece o CPF e o CNPJ com ou sem pontuação e devolve a mesma forma de comparação' do
    lidos = ['123.456.789-09', ' 12345678909 ', '11.222.333/0001-81', '11222333000181'].map { |texto| numero(texto) }

    expect(lidos.map(&:canonico)).to eq(%w[12345678909 12345678909 11222333000181 11222333000181])
    expect(lidos.map(&:tipo)).to eq(%w[cpf cpf cnpj cnpj])
    expect(lidos.map(&:valido?)).to all(be(true))
  end

  it 'aceita o CNPJ novo, com letras, em qualquer caixa, escrito com a pontuação completa' do
    lidos = ['12.abc.345/01de-35', '12.ABC.345/01DE-35', " 12.Abc.345/01dE-35\n"].map { |texto| numero(texto) }

    expect(lidos.map { |lido| [lido.canonico, lido.tipo, lido.valido?] }).to all(eq(['12ABC34501DE35', 'cnpj', true]))
    expect(lidos.map(&:letra_fora_da_forma?)).to all(be(false))
    expect([numero('12.ABC.345/01DE-36').valido?, numero('12.ABC.345/01DE-36').letra_fora_da_forma?]).to eq([false, false])
  end

  # Com letra, só a forma XX.XXX.XXX/XXXX-DD é número: 18 caracteres, cada sinal no seu lugar, os dois últimos dígitos.
  it 'recusa texto com letra fora da forma completa do CNPJ, em qualquer caixa, e diz que foi por isso' do
    fora_da_forma = ['12ABC34501DE35', '12abc34501de35', '12.ABC.345/01DE35', '12ABC.345/01DE-35', '12.ABC-345/01DE.35',
                     '.12ABC.345/01DE-35', '12.ABC.345/01DE-3A', '1234567890A'].map { |texto| numero(texto) }

    expect(fora_da_forma.map { |lido| [lido.canonico, lido.tipo, lido.valido?, lido.letra_fora_da_forma?] }).to all(eq(['', nil, false, true]))
    expect(fora_da_forma.map { |lido| [lido.formatado, lido.mascarado, lido.to_s] }).to all(eq([nil, nil, '']))
  end

  it 'texto só com dígitos nunca é recusado por letra, com a pontuação inteira, pela metade ou sem nenhuma' do
    textos = ['123.456.789-09', '123456789-09', '112223330001-81', '11222333000181', '123.456.789-08', '1234567890', '']
    so_digitos = textos.map { |texto| numero(texto) }

    expect(so_digitos.map(&:letra_fora_da_forma?)).to all(be(false))
    expect(so_digitos.map(&:valido?)).to eq([true, true, true, true, false, false, false])
  end

  it 'lê o que já está guardado na forma de comparação, sem pedir a pontuação do CNPJ com letra' do
    guardados = %w[12ABC34501DE35 11222333000181 12345678909].map { |valor| described_class.guardado(valor) }

    expect(guardados.map(&:valido?)).to all(be(true))
    expect(guardados.map(&:formatado)).to eq(['12.ABC.345/01DE-35', '11.222.333/0001-81', '123.456.789-09'])
    expect(guardados.map(&:letra_fora_da_forma?)).to all(be(false))
  end

  it 'recusa dígito verificador errado, tamanho errado, número repetido, letra no CPF e texto vazio' do
    errados = ['123.456.789-08', '11.222.333/0001-80', '1234567890', '111.111.111-11', '00.000.000/0000-00', '1234567890A', '', nil]

    expect(errados.map { |texto| numero(texto).valido? }).to all(be(false))
  end

  # "CLI" mais os onze dígitos deste CPF dão 14 caracteres que passam na conta do dígito verificador do CNPJ: só tirando
  # espaço e pontuação, o rótulo na frente fazia o CPF de uma pessoa ser guardado como CNPJ. Colado ou com espaço, o
  # rótulo tem letra e o texto não está na forma completa do CNPJ: recusado.
  it 'recusa texto que não é só o número: rótulo na frente, colado ou não, espaço no meio, dois-pontos, outro tipo de traço' do
    com_rotulo = ['CLI 123.456.789-09', 'CLI123.456.789-09', 'CLI12345678909', 'cli12345678909'].map { |texto| numero(texto) }
    outros = ['CPF 12345678909', 'CPF: 123.456.789-09', '123 456 789 09', '123.456.789-09, da Marina', "123.456.789\u201109"]

    expect(com_rotulo.map { |lido| [lido.canonico, lido.tipo, lido.valido?, lido.letra_fora_da_forma?] }).to all(eq(['', nil, false, true]))
    expect(outros.map { |texto| numero(texto).valido? }).to all(be(false))
  end

  it 'aceita espaço e quebra de linha só nas pontas' do
    expect([numero(" 123.456.789-09\n").canonico, numero("\t11.222.333/0001-81 ").canonico]).to eq(%w[12345678909 11222333000181])
  end

  it 'mostra o número pontuado só para quem pede, e mascarado em to_s e inspect' do
    cpf = numero('12345678909')
    cnpj = numero('11222333000181')

    expect([cpf.formatado, cnpj.formatado]).to eq(['123.456.789-09', '11.222.333/0001-81'])
    expect([cpf.mascarado, cnpj.mascarado]).to eq(['***.***.***-09', '**.***.***/****-81'])
    expect(["#{cpf} #{cnpj}", cpf.inspect, cnpj.inspect].join).not_to include('123456789', '123.456.789', '11222333', '11.222.333')
  end

  it 'do que não confere não mostra pedaço nenhum' do
    errado = numero('123.456.789-08')

    expect([errado.formatado, errado.mascarado, errado.to_s]).to eq([nil, nil, ''])
    expect(errado.inspect).not_to include('08')
  end
end
