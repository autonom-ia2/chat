require 'rails_helper'

# A IDENTIDADE DE UM PEDIDO (entrega 10): dois pedidos são o mesmo pedido quando a entrada
# normalizada pelo adapter é a mesma — e valores diferentes são pedidos diferentes, inclusive
# `false`, `nil` e `''` entre si (o adapter os manda como vieram).
RSpec.describe Autonomia::Insurance::Pedido do
  let(:entrada) { { 'vehicle' => { 'plate' => 'ABC1D23', 'isZeroKm' => false }, 'insured' => { 'document' => '1' } } }

  it 'nao depende da ordem das chaves nem de simbolo/texto' do
    invertida = { insured: { document: '1' }, vehicle: { isZeroKm: false, plate: 'ABC1D23' } }
    expect(described_class.digest('auto', invertida)).to eq(described_class.digest('auto', entrada))
    expect(described_class.digest('auto', entrada).length).to eq(described_class::TAMANHO)
  end

  it 'false, nil, vazio e ausente sao quatro pedidos' do
    base = described_class.digest('auto', entrada)
    com = ->(valor) { described_class.digest('auto', entrada.deep_merge('vehicle' => { 'isZeroKm' => valor })) }
    sem = described_class.digest('auto', entrada.merge('vehicle' => entrada['vehicle'].except('isZeroKm')))

    expect([base, com.call(nil), com.call(''), sem].uniq.size).to eq(4)
  end

  it 'o produto faz parte do pedido' do
    expect(described_class.digest('bike', entrada)).not_to eq(described_class.digest('auto', entrada))
  end

  it 'sem entrada nao ha identidade' do
    expect(described_class.digest('auto', nil)).to be_nil
    expect(described_class.digest('auto', {})).to be_nil
  end
end
