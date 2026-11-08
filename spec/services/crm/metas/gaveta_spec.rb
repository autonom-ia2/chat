require 'rails_helper'

# A sugestão da gaveta "Metas do mês" (#1991): a média dos 3 meses, de R$ 500 em R$ 500 a partir de R$ 1.000.
RSpec.describe Crm::Metas::Gaveta do
  it 'arredonda a média de R$ 500 em R$ 500 a partir de R$ 1.000, de 1 em 1 abaixo, e não sugere sem venda' do
    expect(described_class.sugerir([6100, 5700, 6200])).to eq(6000)
    expect(described_class.sugerir([7200, 8400, 7900])).to eq(8000)
    expect(described_class.sugerir([100, 200, 400])).to eq(233)
    expect(described_class.sugerir([0, 0, 0])).to be_nil
  end
end
