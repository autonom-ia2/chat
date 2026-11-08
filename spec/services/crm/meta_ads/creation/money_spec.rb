require 'rails_helper'

# Dinheiro do anúncio (#2198): só o que a tela manda (dígitos e um ponto com até 2 casas), nunca float nem notação que
# o BigDecimal aceitaria sozinho.
RSpec.describe Crm::MetaAds::Creation::Money do
  it 'aceita dígitos com até 2 casas depois do ponto, e o inteiro do JSON' do
    expect(described_class.parse('45')).to eq(BigDecimal(45))
    expect(described_class.parse(' 45.5 ')).to eq(BigDecimal('45.5'))
    expect(described_class.parse('20.57')).to eq(BigDecimal('20.57'))
    expect(described_class.parse(45)).to eq(BigDecimal(45))
  end

  it 'recusa expoente, sublinhado, sinal, vírgula, ponto solto, mais de 2 casas e float' do
    ['1e2', '1E2', '1_000', '-5', '+5', '45,50', '45.', '.5', '1.2.3', '20.005', '', ' ', 'abc', 'Infinity', 'NaN'].each do |value|
      expect(described_class.parse(value)).to be_nil, "#{value.inspect} devia ser recusado"
    end
    expect(described_class.parse(45.5)).to be_nil
    expect(described_class.parse(nil)).to be_nil
  end

  it 'texto para a tela e centavos inteiros' do
    expect(described_class.text(BigDecimal('20.5'))).to eq('20.50')
    expect(described_class.cents(BigDecimal('25.57'))).to eq(2557)
  end
end
