require 'rails_helper'

# E4 (#2897): como a célula da planilha vira a data e o valor de um seguro.
RSpec.describe Carteira::Trazer::Leitores do
  let(:invalido) { described_class::INVALIDO }

  it 'lê a data como o brasileiro escreve, a data ISO e o número de dia do Excel' do
    dia = Date.new(2027, 3, 10)
    escritas = ['2027-03-10', '10/03/2027', '10-03-2027', '10.03.2027', '10/03/27', ' 10/03/2027 ', '10/03/2027 00:00:00',
                '46456']

    expect(escritas.map { |texto| described_class.data(texto) }).to all(eq(dia))
    expect(described_class.data('5/1/2026')).to eq(Date.new(2026, 1, 5))
  end

  it 'a célula vazia não é data nenhuma, e o que não dá para ler é inválido' do
    fora = ['31/02/2027', 'março de 2027', '10/03', '2027', '10/03/1800', '10/-3/2027', '10/03/2027/1', '12345', 'dez/2027']

    expect([nil, '', '   '].map { |texto| described_class.data(texto) }).to all(be_nil)
    expect(fora.map { |texto| described_class.data(texto) }).to all(eq(invalido))
  end

  it 'lê o valor em reais com vírgula ou ponto e devolve centavos' do
    tabela = {
      'R$ 3.410,00' => 341_000, 'R$ 3.410,00' => 341_000, '3410' => 341_000, '3410.5' => 341_050, '3.410' => 341_000,
      '1.234.567,89' => 123_456_789, '890,50' => 89_050, '0,99' => 99, '0.500' => 50, '1234.5600000000001' => 123_456, '0' => 0
    }

    tabela.each { |texto, centavos| expect(described_class.centavos(texto)).to eq(centavos), texto }
  end

  it 'a célula vazia não é valor nenhum, e o que não é número é inválido' do
    expect([nil, '', '  ', 'R$'].map { |texto| described_class.centavos(texto) }).to all(be_nil)
    expect(['a combinar', '-10', '12,34,56', '99999999999999999999'].map { |texto| described_class.centavos(texto) }).to all(eq(invalido))
  end
end
