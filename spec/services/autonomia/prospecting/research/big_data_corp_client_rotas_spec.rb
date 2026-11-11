require 'rails_helper'

# #2858 (F7): o cliente da BigDataCorp da Prospecção em outras rotas (as ferramentas Premium), sem mudar a consulta de
# empresas. Só rotas da lista; a credencial nunca vai a erro nem log.
RSpec.describe Autonomia::Prospecting::Research::BigDataCorpClient do
  let(:base) { 'https://plataforma.bigdatacorp.com.br' }
  let(:credentials) { { username: 'usuario-exemplo', password: 'senha-exemplo-nao-real' } }
  let(:client) { described_class.new(credentials: credentials, sleeper: ->(_) {}, max_provider_attempts: 1) }

  before do
    stub_request(:post, "#{base}/tokens/gerar").to_return(status: 200, body: { token: 'token-exemplo', tokenID: 'id-exemplo' }.to_json)
  end

  it 'consulta outra rota com o mesmo token, Datasets, q e Limit' do
    stub_request(:post, "#{base}/ondemand")
      .with(body: { Datasets: 'ondemand_pgfn_company', q: 'doc{11222333000181}', Limit: 1 }.to_json,
            headers: { 'AccessToken' => 'token-exemplo', 'TokenId' => 'id-exemplo' })
      .to_return(status: 200, body: { Result: [], QueryId: 'query-exemplo' }.to_json)

    resposta = client.query_route('/ondemand', query: 'doc{11222333000181}', datasets: 'ondemand_pgfn_company')

    expect(resposta.metadata[:provider_request_id]).to eq('query-exemplo')
  end

  it 'recusa rota fora da lista, sem chamar nada' do
    expect { client.query_route('/tokens/gerar', query: 'x', datasets: 'y') }.to raise_error(ArgumentError)
    expect(chamou_a_bigdatacorp?).to be(false)
  end

  it 'com uma tentativa só, o 504 não repete' do
    stub_request(:post, "#{base}/empresas").to_return(status: 504, body: '')

    expect { client.query_route('/empresas', query: 'doc{11222333000181}', datasets: 'kyc') }
      .to raise_error(described_class::Error) { |erro| expect([erro.code, erro.status]).to eq(['BIGDATACORP_HTTP_ERROR', 504]) }
    expect(a_request(:post, "#{base}/empresas")).to have_been_made.once
  end

  it 'a consulta de empresas da Prospecção continua igual (rota, corpo e limite padrão)' do
    stub_request(:post, "#{base}/empresas")
      .with(body: { Datasets: 'basic_data', q: 'name{EXEMPLO}', Limit: 3 }.to_json)
      .to_return(status: 200, body: { Result: [] }.to_json)

    expect(client.search_companies(query: 'name{EXEMPLO}').payload).to eq('Result' => [])
  end
end
