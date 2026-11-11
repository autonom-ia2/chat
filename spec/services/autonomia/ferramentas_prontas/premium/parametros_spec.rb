require 'rails_helper'

# #2858 (F7): os parâmetros dos cards Premium normalizam antes de qualquer gasto. O que não normaliza é pedido inválido,
# e a BigDataCorp não é chamada.
RSpec.describe Autonomia::FerramentasProntas::Premium::Parametros do
  it 'placa antiga e Mercosul, com ou sem traço; o resto não serve' do
    expect(described_class::PLACA.normalizar('abc-1234')).to eq('ABC1234')
    expect(described_class::PLACA.normalizar('ABC1D23')).to eq('ABC1D23')
    expect(described_class::PLACA.normalizar('AB12345')).to be_nil
    expect(described_class::PLACA.normalizar('ABC12345')).to be_nil
    expect(described_class::PLACA.normalizar('ABCD123')).to be_nil
  end

  it 'CPF só com dígito verificador certo' do
    expect(described_class::CPF.normalizar('111.444.777-35')).to eq('11144477735')
    expect(described_class::CPF.normalizar('111.444.777-36')).to be_nil
    expect(described_class::CPF.normalizar('11111111111')).to be_nil
  end

  it 'CNPJ não aceita um CPF' do
    expect(described_class::CNPJ.normalizar('11.222.333/0001-81')).to eq('11222333000181')
    expect(described_class::CNPJ.normalizar('111.444.777-35')).to be_nil
  end

  it 'número do imóvel só com dígitos' do
    expect(described_class::NUMERO.normalizar('123')).to eq('123')
    expect(described_class::NUMERO.normalizar('s/n')).to be_nil
    expect(described_class::NUMERO.normalizar('12 apto 3')).to be_nil
  end

  it 'código do CAR com estado do Brasil, município e 32 posições' do
    codigo = "MT-5107065-#{'EXEMPLO0' * 4}"
    expect(described_class::CODIGO_CAR.normalizar(codigo)).to eq("MT5107065#{'EXEMPLO0' * 4}")
    expect(described_class::CODIGO_CAR.normalizar("XX5107065#{'EXEMPLO0' * 4}")).to be_nil
    expect(described_class::CODIGO_CAR.normalizar('MT5107065')).to be_nil
  end
end
