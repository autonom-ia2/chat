require 'rails_helper'

RSpec.describe Autonomia::Agents::Tools::Native::SeguroViagem::Pedido do
  let(:hoje) { Date.new(2026, 11, 24) }
  let(:base) { { 'destinos' => ['pt'], 'data_saida' => '2027-02-02', 'data_retorno' => '2027-02-06', 'idades' => [45] } }

  it 'idade vira data técnica: saída − idade anos − 6 meses' do
    pedido, = described_class.new(base, hoje: hoje, tarifa_acordo: false).conferir
    expect(pedido['passageiros']).to eq([{ 'nome' => 'Viajante 1', 'dataNascimento' => '1981-08-02' }])
    expect(pedido['destinos']).to eq(['PT'])
  end

  it 'tarifa: Acordo com tarifaAcordo, senão Folheto (nunca 0)' do
    expect(described_class.new(base, hoje: hoje, tarifa_acordo: true).conferir.first['tipoTarifa']).to eq(2)
    expect(described_class.new(base, hoje: hoje, tarifa_acordo: false).conferir.first['tipoTarifa']).to eq(1)
  end

  it 'motivo vira classificação; sem motivo é 1' do
    { nil => 1, 'lazer' => 4, 'estudo' => 5, 'negocios' => 6, 'gestante' => 7, 'cruzeiro' => 8 }.each do |motivo, codigo|
      expect(described_class.new(base.merge('motivo' => motivo), hoje: hoje, tarifa_acordo: false).conferir.first['classificacoes'])
        .to eq([codigo])
    end
  end

  it 'pedido fixo da viagem única' do
    pedido, = described_class.new(base, hoje: hoje, tarifa_acordo: false).conferir
    expect(pedido.slice('tipoViagem', 'produtoAvulso', 'cupom')).to eq('tipoViagem' => 1, 'produtoAvulso' => false, 'cupom' => '')
  end

  it 'recusas com o campo' do
    { { 'data_saida' => '2026-11-23' } => 'data_saida', { 'data_retorno' => '2027-02-01' } => 'data_retorno',
      { 'data_saida' => '02/02/2027' } => 'data_saida', { 'idades' => [] } => 'idades', { 'idades' => [121] } => 'idades',
      { 'destinos' => [] } => 'destinos', { 'destinos' => ['PRT'] } => 'destinos', { 'motivo' => 'ferias' } => 'motivo' }.each do |troca, campo|
      _, falta = described_class.new(base.merge(troca), hoje: hoje, tarifa_acordo: false).conferir
      expect(falta.campo).to eq(campo)
    end
  end

  it 'saída hoje é aceita' do
    expect(described_class.new(base.merge('data_saida' => '2026-11-24'), hoje: hoje, tarifa_acordo: false).conferir.last).to be_nil
  end
end
