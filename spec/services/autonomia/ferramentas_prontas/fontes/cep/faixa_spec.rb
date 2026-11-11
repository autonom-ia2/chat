require 'rails_helper'

# #2858 (F7, C15c/C15d do testador): a faixa de número que o ViaCEP manda no `complemento` de cada CEP da rua, lida com
# método de string (sem regex). Os textos são os reais do ViaCEP (Rua Augusta, São Paulo; Rua Sete de Setembro, Campinas).
RSpec.describe Autonomia::FerramentasProntas::Fontes::Cep::Faixa do
  it 'até N, com o lado' do
    expect(described_class.cobre?('até 698 - lado par', '100')).to be(true)
    expect(described_class.cobre?('até 698 - lado par', '101')).to be(false)
    expect(described_class.cobre?('até 697 - lado ímpar', '101')).to be(true)
    expect(described_class.cobre?('até 697 - lado ímpar', '699')).to be(false)
  end

  it 'de N a M, e de N ao fim' do
    expect(described_class.cobre?('de 700 a 1680 - lado par', '700')).to be(true)
    expect(described_class.cobre?('de 700 a 1680 - lado par', '1682')).to be(false)
    expect(described_class.cobre?('de 2440 ao fim - lado par', '9000')).to be(true)
    expect(described_class.cobre?('de 2431 ao fim - lado ímpar', '2430')).to be(false)
    expect(described_class.cobre?('de 611 a 1045', '700')).to be(true)
  end

  it 'o número exato do CEP de um prédio, e a faixa com barra' do
    expect(described_class.cobre?('189', '189')).to be(true)
    expect(described_class.cobre?('189', '190')).to be(false)
    expect(described_class.cobre?('até 1159/1160', '1160')).to be(true)
    expect(described_class.cobre?('de 1161/1162 ao fim', '1161')).to be(true)
  end

  it 'só o lado: a rua inteira daquele lado' do
    expect(described_class.cobre?('lado par', '10')).to be(true)
    expect(described_class.cobre?('lado ímpar', '10')).to be(false)
  end

  # Revisor (lote 3): o lado com um trecho que não é faixa dizia "cobre" para qualquer número daquele lado.
  it 'o lado com um trecho que não é faixa: nil, não true' do
    expect(described_class.cobre?('2766 Anexo 2770 - lado par', '10')).to be_nil
    expect(described_class.cobre?('2766 Anexo 2770 - lado par', '11')).to be(false)
  end

  it 'sem faixa, texto que não é faixa ou número que não é número: nil (não dá para dizer)' do
    expect(described_class.cobre?('', '10')).to be_nil
    expect(described_class.cobre?(nil, '10')).to be_nil
    expect(described_class.cobre?('2766 Anexo 2770', '2766')).to be_nil
    expect(described_class.cobre?('até 698 - lado par', 's/n')).to be_nil
  end

  it '.exato?: só o CEP de prédio cujo complemento é o próprio número' do
    expect(described_class.exato?('1260', '1260')).to be(true)
    expect(described_class.exato?(' 1260 ', 1260)).to be(true)
    expect(described_class.exato?('1260', '1262')).to be(false)
    expect(described_class.exato?('de 700 a 1680 - lado par', '1260')).to be(false)
    expect(described_class.exato?('1159/1160', '1159')).to be(false)
    expect(described_class.exato?('', '1260')).to be(false)
    expect(described_class.exato?('1260', 's/n')).to be(false)
  end
end
