require 'rails_helper'

# #3099: a vencedora pela régua da tela (vencedora.js): números redondos "de cada 100", até 15% é empate, poucas
# respostas é cedo demais.
RSpec.describe CampaignJourney::DuasVersoes::Vencedora, :aggregate_failures do
  def versao(receberam, responderam, compraram = 0)
    { receberam: receberam, responderam: responderam, compraram: compraram }
  end

  it 'escolhe a que tem mais respostas de cada 100' do
    expect(described_class.melhor(versao(100, 9), versao(100, 18), 'respostas')).to eq(2)
    expect(described_class.melhor(versao(100, 30), versao(100, 12), 'respostas')).to eq(1)
  end

  it 'até 15% de diferença é empate' do
    expect(described_class.melhor(versao(100, 20), versao(100, 22), 'respostas')).to be_nil
    expect(described_class.melhor(versao(100, 20), versao(100, 23), 'respostas')).to eq(2)
  end

  it 'com poucas respostas somadas é cedo demais' do
    expect(described_class.melhor(versao(100, 1), versao(100, 8), 'respostas')).to be_nil
  end

  it 'compara pelos números redondos que a tela mostra' do
    expect(described_class.melhor(versao(300, 37), versao(299, 37), 'respostas')).to be_nil
  end

  it 'só uma versão teve resultado: ela ganha' do
    expect(described_class.melhor(versao(100, 0), versao(100, 10), 'respostas')).to eq(2)
  end

  it 'no critério compras, conta compras e passa para "de cada 1.000" quando a taxa é baixa' do
    expect(described_class.melhor(versao(2000, 50, 4), versao(2000, 10, 12), 'compras')).to eq(2)
    expect(described_class.de_cada(versao(2000, 0, 4), versao(2000, 0, 12), :compraram)).to eq([2, 6])
  end
end
