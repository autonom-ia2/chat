require 'rails_helper'

RSpec.describe Autonomia::Agents::Tools::Native::SeguroViagem::Dinheiro do
  it 'reais com milhar e duas casas' do
    expect(described_class.brl('1480.25')).to eq('R$ 1.480,25')
    expect(described_class.brl(360)).to eq('R$ 360,00')
  end
end
