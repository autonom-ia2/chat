require 'rails_helper'

# #2858 — regra "QI 70": a cidade basta. A UF só é pedida quando o nome existe em mais de um estado.
RSpec.describe Autonomia::FerramentasProntas::Municipios do
  it 'so o nome, cidade unica no Brasil: acha, sem acento e sem caixa' do
    expect(described_class.buscar(nil, 'uberlandia')).to have_attributes(nome: 'Uberlândia', uf: 'MG', codigo: '3170206')
  end

  it 'com a UF: a UF tem precedencia, e cidade de outro estado nao acha' do
    expect(described_class.buscar('to', 'Palmas')).to have_attributes(uf: 'TO')
    expect(described_class.buscar('SP', 'Uberlândia')).to be_nil
  end

  it 'UF errada para cidade unica ("Uberlandia, SP"): recusa na uf, com a UF certa como candidata' do
    falta = described_class.falta('SP', 'Uberlândia')

    expect(falta).to have_attributes(campo: 'uf', candidatos: ['MG'])
    expect(falta.orientacao).to include('Uberlândia', 'MG')
  end

  it 'homonima sem UF: nao escolhe por conta propria' do
    expect(described_class.buscar(nil, 'Bom Jesus')).to be_nil
  end

  it 'falta: nil quando acha; a UF com as candidatas quando homonima; a cidade quando nao existe' do
    expect(described_class.falta(nil, 'Uberlândia')).to be_nil
    expect(described_class.falta(nil, 'Bom Jesus')).to have_attributes(campo: 'uf', candidatos: %w[PB PI RN RS SC])
    expect(described_class.falta(nil, 'Bom Jesus').orientacao).to include('PB, PI, RN, RS, SC', 'pergunte ao cliente')
    expect(described_class.falta('MG', 'Bom Jesus')).to have_attributes(campo: 'uf', candidatos: %w[PB PI RN RS SC])
    expect(described_class.falta(nil, 'Nao Existe')).to have_attributes(campo: 'cidade')
    expect(described_class.falta(nil, nil)).to have_attributes(campo: 'cidade')
  end
end
