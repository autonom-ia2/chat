require 'rails_helper'

RSpec.describe Autonomia::Agents::Tools::Native::SeguroViagem::PorDia do
  let(:plano) { { 'codigo' => 'P1', 'preco_total' => '100.0', 'multiviagem' => false } }
  let(:pedido) { { 'data_saida' => '2027-03-10', 'data_retorno' => '2027-03-12', 'idades' => [40] } }

  it 'conta os dias como o PDF: ida e volta inclusive' do
    expect(described_class.dias(Date.new(2027, 2, 2), Date.new(2027, 2, 6))).to eq(5)
    expect(described_class.dias(Date.new(2027, 2, 2), Date.new(2027, 2, 2))).to eq(1)
  end

  it 'total ÷ dias ÷ viajantes, arredondado para baixo em centavos' do
    # 3 dias, 1 viajante: 33,333... vira 33,33; 2 viajantes: 16,666... vira 16,66, nunca 16,67.
    expect(described_class.por_pessoa(plano, pedido)).to eq('R$ 33,33')
    expect(described_class.por_pessoa(plano, pedido.merge('idades' => [40, 38]))).to eq('R$ 16,66')
  end

  it 'em reais com milhar e duas casas, como o resto da cotação' do
    expect(described_class.por_pessoa(plano.merge('preco_total' => '3600.0'), pedido.merge('data_retorno' => '2027-03-10')))
      .to eq('R$ 3.600,00')
  end

  it 'plano anual não tem preço por dia' do
    expect(described_class.por_pessoa(plano.merge('multiviagem' => true), pedido)).to be_nil
  end

  it 'sem preço, sem datas válidas, volta antes da ida ou sem viajantes: nil, nunca um valor inventado' do
    expect(described_class.por_pessoa(plano.merge('preco_total' => nil), pedido)).to be_nil
    expect(described_class.por_pessoa(plano, pedido.except('data_retorno'))).to be_nil
    expect(described_class.por_pessoa(plano, pedido.merge('data_saida' => '2027-02-30'))).to be_nil
    expect(described_class.por_pessoa(plano, pedido.merge('data_retorno' => '2027-03-01'))).to be_nil
    expect(described_class.por_pessoa(plano, pedido.merge('idades' => []))).to be_nil
  end
end
