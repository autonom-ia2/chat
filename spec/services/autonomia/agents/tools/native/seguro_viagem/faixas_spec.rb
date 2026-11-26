require 'rails_helper'

RSpec.describe Autonomia::Agents::Tools::Native::SeguroViagem::Faixas do
  let(:plano) do
    { 'idade_minima' => 0, 'idade_maxima' => 85,
      'faixas' => [{ 'de' => 0, 'ate' => 64, 'valor' => '120.0' }, { 'de' => 65, 'ate' => 75, 'valor' => '240.0' },
                   { 'de' => 76, 'ate' => 85, 'valor' => '480.0' }] }
  end

  it 'faixa da idade; fora do limite é nil' do
    expect(described_class.faixa(plano, 70)['valor']).to eq('240.0')
    expect(described_class.faixa(plano, 90)).to be_nil
  end

  it 'idade nil é nil' do
    expect(described_class.faixa(plano, nil)).to be_nil
  end

  it 'sem faixas é nil' do
    expect(described_class.faixa({ 'idade_minima' => 0, 'idade_maxima' => 85 }, 30)).to be_nil
  end

  it 'preço por pessoa na ordem das idades' do
    expect(described_class.precos_por_pessoa(plano, [45, 70, 90])).to eq(['120.0', '240.0', nil])
  end

  it 'idade na data da saída' do
    expect(described_class.idade_em(Date.new(1981, 3, 15), Date.new(2027, 2, 2))).to eq(45)
    expect(described_class.idade_em(Date.new(1981, 2, 2), Date.new(2027, 2, 2))).to eq(46)
  end

  it 'mesma faixa por multiset, não pela ordem' do
    expect(described_class.mesma_faixa?(plano, [45, 70], [71, 44])).to be(true)
    expect(described_class.mesma_faixa?(plano, [45], [66])).to be(false)
    expect(described_class.mesma_faixa?(plano, [45], [90])).to be(false)
  end

  it 'mesma faixa conta quantos caem em cada uma' do
    expect(described_class.mesma_faixa?(plano, [45, 70], [45, 44])).to be(false)
  end
end
