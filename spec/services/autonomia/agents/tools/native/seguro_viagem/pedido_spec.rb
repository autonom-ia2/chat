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

  # Medido em 26/11: X3 (América do Sul mais Brasil) e Y5 (EUA com Orlando) existem na lista e voltam sem plano.
  it 'X3 e Y5 são recusados com o código que cota' do
    %w[X3 y5].each do |codigo|
      _, falta = described_class.new(base.merge('destinos' => [codigo]), hoje: hoje, tarifa_acordo: false).conferir
      expect(falta).to have_attributes(campo: 'destinos', texto: include('X9', 'US'))
    end
  end

  # #3226: a região vai pelo código da Universal (letra + letra ou dígito). Começar por dígito ou ter um caractere só
  # não é código de nada na Universal; a lista dela confere o resto.
  it 'código de região (X4, X6, Y6) passa; "X", "4X", "X-" e "XYZ" não' do
    %w[x4 X6 Y6].each do |codigo|
      pedido, falta = described_class.new(base.merge('destinos' => [codigo]), hoje: hoje, tarifa_acordo: false).conferir
      expect(falta).to be_nil
      expect(pedido['destinos']).to eq([codigo.upcase])
    end
    %w[X 4X X- XYZ].each do |codigo|
      _, falta = described_class.new(base.merge('destinos' => [codigo]), hoje: hoje, tarifa_acordo: false).conferir
      expect(falta.campo).to eq('destinos')
    end
  end

  describe 'o Brasil sai quando há país de fora (#3226)' do
    def conferido(destinos, nomes = nil)
      params = base.merge('destinos' => destinos)
      params['nomes_dos_destinos'] = nomes if nomes
      described_class.new(params, hoje: hoje, tarifa_acordo: false)
    end

    it 'BR com AR vira só AR, e o nome do Brasil sai da mesma posição' do
      pedido = conferido(%w[br AR], %w[Brasil Argentina])
      expect(pedido.conferir.first['destinos']).to eq(['AR'])
      expect(pedido.brasil_fora?).to be(true)
      expect(pedido.nomes_dos_destinos).to eq(['Argentina'])
    end

    it 'só o Brasil fica o Brasil, sem aviso' do
      pedido = conferido(%w[BR br], ['Brasil'])
      expect(pedido.conferir.first['destinos']).to eq(['BR'])
      expect(pedido.brasil_fora?).to be(false)
      expect(pedido.nomes_dos_destinos).to eq(['Brasil'])
    end

    it 'nomes de outro tamanho ficam como vieram' do
      expect(conferido(%w[BR AR], ['Argentina']).nomes_dos_destinos).to eq(['Argentina'])
    end
  end

  it 'saída hoje é aceita' do
    expect(described_class.new(base.merge('data_saida' => '2026-11-24'), hoje: hoje, tarifa_acordo: false).conferir.last).to be_nil
  end
end
