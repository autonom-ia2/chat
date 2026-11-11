require 'rails_helper'

# #2906 — a AwesomeAPI, reserva do endereço pelo CEP (decisão do Rodrigo, 11/11/2026: mais de uma fonte, para ter margem
# no limite de pedidos). As respostas são as reais, medidas em 11/11/2026.
RSpec.describe Autonomia::FerramentasProntas::Fontes::Cep::AwesomeApi do
  let(:url) { 'https://cep.awesomeapi.com.br/json/01001000' }
  let(:consulta) { Autonomia::FerramentasProntas::Fontes::Cep::FONTE.consulta('endereco') }
  let(:da_fonte) do
    { cep: '01001000', address_type: 'Praça', address_name: 'da Sé', address: 'Praça da Sé', state: 'SP', district: 'Sé',
      lat: '-23.5500806', lng: '-46.6340827', city: 'São Paulo', city_ibge: '3550308', ddd: '11' }
  end

  before { resolver_hosts_das_prontas }

  def consultar(cep = '01001000')
    cliente = Autonomia::FerramentasProntas::ClienteHttp.new(hosts: [described_class.host],
                                                             prazo_final: Autonomia::FerramentasProntas::ClienteHttp.agora + 5)
    described_class.new(cliente, prazo: 3).consultar(consulta, 'cep' => cep)
  end

  it 'so atende o endereco pelo CEP (nao busca o CEP pela rua)' do
    expect(described_class.aplica?(consulta, {})).to be(true)
    expect(described_class.aplica?(Autonomia::FerramentasProntas::Fontes::Cep::FONTE.consulta('por_endereco'), {})).to be(false)
  end

  it '200: o endereco enxuto, sem latitude, longitude, DDD nem codigo IBGE' do
    fonte_responde(url, da_fonte)

    expect(consultar).to eq('cep' => '01001-000', 'logradouro' => 'Praça da Sé', 'bairro' => 'Sé', 'cidade' => 'São Paulo', 'uf' => 'SP')
  end

  it '404 (o CEP que nao existe): nao encontrado' do
    fonte_responde('https://cep.awesomeapi.com.br/json/99999999', { code: 'not_found', message: 'O CEP 99999999 nao foi encontrado' },
                   status: 404)

    expect { consultar('99999999') }.to raise_error(Autonomia::FerramentasProntas::Provedor::NaoEncontrado)
  end

  it 'sem a cidade ou a UF (a fonte mudou o formato): falha, e a proxima tenta' do
    fonte_responde(url, da_fonte.except(:city))

    expect { consultar }.to raise_error(Autonomia::FerramentasProntas::Provedor::Falha, 'resposta_invalida')
  end

  it 'sem a rua nem o bairro (CEP geral de cidade pequena): so a cidade e a UF' do
    fonte_responde(url, da_fonte.merge(address: '', district: ''))

    expect(consultar).to eq('cep' => '01001-000', 'cidade' => 'São Paulo', 'uf' => 'SP')
  end

  it 'com a chave no ambiente, manda o cabecalho x-api-key; sem ela, nao manda' do
    fonte_responde(url, da_fonte)

    with_modified_env(AUTONOMIA_AWESOMEAPI_CHAVE: 'chave-de-teste') { consultar }
    expect(a_request(:get, url).with(headers: { 'X-Api-Key' => 'chave-de-teste' })).to have_been_made.once

    with_modified_env(AUTONOMIA_AWESOMEAPI_CHAVE: '') { consultar }
    expect(a_request(:get, url).with { |pedido| !pedido.headers.key?('X-Api-Key') }).to have_been_made.once
  end

  it 'a chave colada com quebra de linha no meio nao vale (seria outro cabecalho)' do
    with_modified_env(AUTONOMIA_AWESOMEAPI_CHAVE: "chave\r\nX-Outro: 1") do
      expect(described_class.cabecalhos).to eq({})
    end
  end
end
