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

  it 'aceita o CNPJ novo, com letras, em qualquer caixa' do
    com_letras = numero('12.abc.345/01de-35')

    expect([com_letras.canonico, com_letras.tipo, com_letras.valido?]).to eq(['12ABC34501DE35', 'cnpj', true])
    expect(numero('12.ABC.345/01DE-36').valido?).to be(false)
  end

  it 'recusa dígito verificador errado, tamanho errado, número repetido, letra no CPF e texto vazio' do
    errados = ['123.456.789-08', '11.222.333/0001-80', '1234567890', '111.111.111-11', '00.000.000/0000-00', '1234567890A', '', nil]

    expect(errados.map { |texto| numero(texto).valido? }).to all(be(false))
  end

  # "CLI" mais os onze dígitos deste CPF dão 14 caracteres que passam na conta do dígito verificador do CNPJ: só tirando
  # espaço e pontuação, o rótulo na frente fazia o CPF de uma pessoa ser guardado como CNPJ.
  it 'recusa texto que não é só o número: rótulo na frente, espaço no meio, dois-pontos, outro tipo de traço' do
    com_rotulo = numero('CLI 123.456.789-09')
    outros = ['CPF 12345678909', 'CPF: 123.456.789-09', '123 456 789 09', '123.456.789-09, da Marina', "123.456.789\u201109"]

    expect([com_rotulo.canonico, com_rotulo.tipo, com_rotulo.valido?]).to eq(['', nil, false])
    expect(outros.map { |texto| numero(texto).valido? }).to all(be(false))
    expect([numero('CLI12345678909').tipo, numero('CLI12345678909').valido?]).to eq(['cnpj', true])
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
