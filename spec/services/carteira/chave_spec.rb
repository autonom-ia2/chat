require 'rails_helper'

# E4 (#2897): a forma de comparação da seguradora e do número, que decide o que é "a mesma apólice".
RSpec.describe Carteira::Chave do
  it 'tira espaço, caixa, acento e pontuação da seguradora' do
    escritas = ['Seguradora Exemplo S.A.', ' seguradora  EXEMPLO sa ', 'Segúradôra-Exemplo/S.A', "Seguradora\tExemplo S A"]

    expect(escritas.map { |texto| described_class.seguradora(texto) }.uniq).to eq(['seguradoraexemplosa'])
  end

  it 'deixa o número só com letra e dígito, em maiúscula' do
    escritas = ['EX-001234', 'ex 001.234', ' Ex/001234 ']

    expect(escritas.map { |texto| described_class.numero(texto) }.uniq).to eq(['EX001234'])
  end

  it 'devolve vazio para o que não tem letra nem dígito, e para nada' do
    expect(['---', ' ', '', nil].map { |texto| [described_class.seguradora(texto), described_class.numero(texto)] }).to all(eq(['', '']))
  end

  it 'não muda com o idioma de quem pede' do
    chaves = %i[en pt_BR].map { |idioma| I18n.with_locale(idioma) { described_class.seguradora('Seguradora São João') } }

    expect(chaves).to eq(%w[seguradorasaojoao seguradorasaojoao])
  end
end
