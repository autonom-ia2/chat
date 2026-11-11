require 'rails_helper'

# #2858 — o "CEP de referência da cidade" (regra "QI 70"): para a fonte cujo dado é por cidade e que pede um CEP só para
# saber a cidade, a plataforma acha um CEP daquela cidade sozinha, sem perguntar ao cliente. Quem usa: a F7.
RSpec.describe Autonomia::FerramentasProntas::Fontes::Cep::Referencia do
  let(:uberlandia) { 'https://viacep.com.br/ws/MG/Uberlandia/Rua/json/' }
  let(:serra) { 'https://viacep.com.br/ws/MG/Serra%20da%20Saudade/Rua/json/' }

  before do
    resolver_hosts_das_prontas
    cache_em_memoria
  end

  def rua(cep, bairro, ibge: '3170206')
    { cep: cep, logradouro: 'Rua A', bairro: bairro, localidade: 'Uberlândia', uf: 'MG', ibge: ibge }
  end

  it 'cidade com CEP por rua: o menor CEP da propria cidade (conferido pelo codigo IBGE)' do
    fonte_responde(uberlandia, [rua('38410-776', 'Élisson Prieto'), rua('38400-263', 'Tabajaras'), rua('01001-000', 'Outra', ibge: '3550308')])

    expect(described_class.cep_da_cidade(cidade: 'Uberlândia')).to eq('38400-263')
  end

  it 'cidade de CEP unico: o CEP geral da cidade, que o ViaCEP devolve sem rua' do
    fonte_responde(serra, [{ cep: '35617-000', logradouro: '', bairro: '', localidade: 'Serra da Saudade', uf: 'MG', ibge: '3166600' }])

    expect(described_class.cep_da_cidade(cidade: 'Serra da Saudade', uf: 'mg')).to eq('35617-000')
  end

  it 'guarda por 30 dias: a segunda vez nao chama a fonte' do
    pedido = fonte_responde(uberlandia, [rua('38400-263', 'Tabajaras')])

    2.times { described_class.cep_da_cidade(cidade: 'Uberlândia') }

    expect(pedido).to have_been_requested.once
  end

  it 'cidade homonima sem UF, cidade que nao existe, fonte fora ou sem resposta: nil (quem chama decide)' do
    fonte_fora(uberlandia)

    expect(described_class.cep_da_cidade(cidade: 'Bom Jesus')).to be_nil
    expect(described_class.cep_da_cidade(cidade: 'Nao Existe')).to be_nil
    expect(described_class.cep_da_cidade(cidade: 'Uberlândia')).to be_nil
    expect(a_request(:get, /Bom|Nao/)).not_to have_been_made
  end
end
