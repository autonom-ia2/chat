require 'rails_helper'

# O papel de CRM › Números (#1897), a régua que o "Só eu" e a gaveta de metas (#1991) usam.
RSpec.describe Crm::Numeros::Papel do
  it 'vem do que a pessoa fechou ou tem aberto; sem nada, dos funis que ela enxerga; sem funil, vende' do
    expect(described_class.de(vendeu: true, atendeu: false) { raise 'não devia ler os funis' }).to eq([:venda])
    expect(described_class.de(vendeu: false, atendeu: true) { [true] }).to eq([:atende])
    expect(described_class.de(vendeu: true, atendeu: true) { [] }).to eq(%i[venda atende])
    expect(described_class.de(vendeu: false, atendeu: false) { [false] }).to eq([:atende])
    expect(described_class.de(vendeu: false, atendeu: false) { [true, false] }).to eq(%i[venda atende])
    expect(described_class.de(vendeu: false, atendeu: false) { [] }).to eq([:venda])
  end
end
