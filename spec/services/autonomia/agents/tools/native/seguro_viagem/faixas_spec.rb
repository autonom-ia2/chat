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
end
