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

  describe 'o 401 com uma tentativa só' do
    it 'sem o reenvio (a Prospecção), levanta como antes, mas apaga o token: a consulta seguinte gera outro' do
      stub_request(:post, "#{base}/empresas").to_return({ status: 401, body: '' }, { status: 200, body: { Result: [] }.to_json })

      expect { client.query_route('/empresas', query: 'doc{11222333000181}', datasets: 'kyc') }
        .to raise_error(described_class::Error) { |erro| expect([erro.code, erro.status]).to eq(['BIGDATACORP_HTTP_ERROR', 401]) }
      expect(client.query_route('/empresas', query: 'doc{11222333000181}', datasets: 'kyc').payload).to eq('Result' => [])
      expect(a_request(:post, "#{base}/tokens/gerar")).to have_been_made.twice
      expect(a_request(:post, "#{base}/empresas")).to have_been_made.twice
    end

    it 'com resend_after_unauthorized, um reenvio com token novo; o token recusado sai do token_cache' do
      cache = Autonomia::FerramentasProntas::Premium::Tokens.new
      cliente = described_class.new(credentials: credentials, sleeper: ->(_) {}, max_provider_attempts: 1, token_cache: cache,
                                    resend_after_unauthorized: true)
      stub_request(:post, "#{base}/empresas").to_return({ status: 401, body: '' }, { status: 200, body: { Result: [] }.to_json })

      expect(cliente.query_route('/empresas', query: 'doc{11222333000181}', datasets: 'kyc').metadata)
        .to include(provider_attempts: 2, token_generations: 2)
      expect(a_request(:post, "#{base}/empresas")).to have_been_made.twice
    end

    it 'a Prospecção com 3 tentativas segue igual: 401, token novo e a consulta responde' do
      prospeccao = described_class.new(credentials: credentials, sleeper: ->(_) {})
      stub_request(:post, "#{base}/empresas").to_return({ status: 401, body: '' }, { status: 200, body: { Result: [] }.to_json })

      expect(prospeccao.search_companies(query: 'name{EXEMPLO}').metadata).to include(provider_attempts: 2, token_generations: 2)
      expect(described_class::DEFAULTS[:resend_after_unauthorized]).to be(false)
    end

    it 'a Prospecção não reenvia além das 3 tentativas quando o 401 vem na última' do
      prospeccao = described_class.new(credentials: credentials, sleeper: ->(_) {})
      stub_request(:post, "#{base}/empresas").to_return({ status: 503, body: '' }, { status: 503, body: '' }, { status: 401, body: '' })

      expect { prospeccao.search_companies(query: 'name{EXEMPLO}') }
        .to raise_error(described_class::Error) { |erro| expect(erro.status).to eq(401) }
      expect(a_request(:post, "#{base}/empresas")).to have_been_made.times(3)
    end
  end

  describe 'as opções da F7 (token_timeout e token_cache)' do
    before { stub_request(:post, "#{base}/empresas").to_return(status: 200, body: { Result: [] }.to_json) }

    it 'sem as opções, a Prospecção segue igual: o token é da instância e o prazo do token é o da consulta' do
      2.times { described_class.new(credentials: credentials, sleeper: ->(_) {}).search_companies(query: 'name{EXEMPLO}') }

      expect(a_request(:post, "#{base}/tokens/gerar")).to have_been_made.twice
      expect(client.timeout_for('/tokens/gerar')).to eq(described_class::DEFAULTS[:timeout])
    end

    it 'com token_cache, a instância seguinte reaproveita o token; com token_timeout, o prazo do token é o próprio' do
      cache = Autonomia::FerramentasProntas::Premium::Tokens.new
      novo = -> { described_class.new(credentials: credentials, sleeper: ->(_) {}, token_cache: cache, token_timeout: 3, timeout: 20) }

      novo.call.search_companies(query: 'name{EXEMPLO}')
      novo.call.search_companies(query: 'name{EXEMPLO}')

      expect(a_request(:post, "#{base}/tokens/gerar")).to have_been_made.once
      expect([novo.call.timeout_for('/tokens/gerar'), novo.call.timeout_for('/empresas')]).to eq([3, 20])
      expect(cache.inspect).not_to include('token-exemplo')
    end
  end
end
