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

  describe '.cep (o que a F7 chama em Premium::Endereco.cep)' do
    let(:paulista) { 'https://viacep.com.br/ws/SP/Sao%20Paulo/Avenida%20Paulista/json/' }
    let(:de_sp) { { logradouro: 'Avenida Paulista', localidade: 'São Paulo', uf: 'SP', ibge: '3550308' } }

    it 'sem rua: o CEP de referencia da cidade' do
      fonte_responde(uberlandia, [rua('38400-263', 'Tabajaras')])

      expect(described_class.cep(cidade: 'Uberlândia', uf: 'MG')).to eq('cep' => '38400-263')
    end

    it 'com a rua: um CEP so vira cep; varios viram candidatos, o da rua antes do especial; o bairro filtra' do
      fonte_responde(paulista, [de_sp.merge(cep: '01311-921', complemento: '1159', bairro: 'Bela Vista'),
                                de_sp.merge(cep: '01310-100', complemento: 'de 1 a 609 - lado ímpar', bairro: 'Bela Vista'),
                                de_sp.merge(cep: '01311-000', complemento: 'de 611 a 1045', bairro: 'Cerqueira César')])

      candidatos = described_class.cep(cidade: 'São Paulo', uf: 'SP', rua: 'Avenida Paulista')['candidatos']

      expect(candidatos.pluck('cep')).to eq(%w[01310-100 01311-000 01311-921])
      expect(candidatos.first).to include('bairro' => 'Bela Vista', 'complemento' => 'de 1 a 609 - lado ímpar')
      expect(described_class.cep(cidade: 'São Paulo', uf: 'SP', rua: 'Avenida Paulista', bairro: 'cerqueira')).to eq('cep' => '01311-000')
    end

    it 'rua que nao existe, cidade que nao existe ou fonte fora: nil' do
      fonte_responde(paulista, [])

      expect(described_class.cep(cidade: 'São Paulo', uf: 'SP', rua: 'Avenida Paulista')).to be_nil
      expect(described_class.cep(cidade: 'Nao Existe', uf: 'SP', rua: 'Rua A')).to be_nil
    end
  end
end
