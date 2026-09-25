require 'rails_helper'

# Porte de lib/services/bigdatacorp/client.test.ts do Orth, só a consulta de empresas (#679).
# Fora do porte, por decisão do Rodrigo: cercas financeiras, retomada durável e contabilidade de tentativas.
RSpec.describe Autonomia::Prospecting::Research::BigDataCorpClient do
  let(:token_url) { 'https://plataforma.bigdatacorp.com.br/tokens/gerar' }
  let(:companies_url) { 'https://plataforma.bigdatacorp.com.br/empresas' }
  let(:credentials) { { username: 'fixture-user-secret', password: 'fixture-password-secret' } }
  let(:sleeps) { [] }
  let(:log_lines) { [] }
  let(:logger) do
    lines = log_lines
    Class.new do
      define_method(:warn) { |message| lines << message }
      define_method(:info) { |message| lines << message }
    end.new
  end
  let(:client) { build_client }

  def build_client(**)
    recorded = sleeps
    described_class.new(credentials: credentials, sleeper: ->(seconds) { recorded << seconds }, logger: logger, **)
  end

  def json_response(body, status = 200)
    { status: status, body: body.to_json, headers: { 'Content-Type' => 'application/json' } }
  end

  def token_response(access = 'fixture-access-secret', token_id = 'fixture-token-id-secret')
    json_response({ token: access, tokenID: token_id })
  end

  def search
    client.search_companies(query: 'name{Acme}')
  end

  def captured_error
    yield
    raise 'era esperado um erro'
  rescue described_class::Error => e
    e
  end

  it 'gera token e tokenID no servidor e autentica a consulta com os cabeçalhos exigidos' do
    stub_request(:post, token_url).to_return(token_response)
    companies = stub_request(:post, companies_url)
                .with(headers: { 'AccessToken' => 'fixture-access-secret', 'TokenId' => 'fixture-token-id-secret' },
                      body: { Datasets: 'basic_data', q: 'name{Acme}', Limit: 3 }.to_json)
                .to_return(json_response({ QueryId: 'query-from-body-1', Result: [] }).merge(headers: { 'x-request-id' => 'untrusted' }))

    result = search

    expect(companies).to have_been_requested.once
    expect(result.payload).to eq('QueryId' => 'query-from-body-1', 'Result' => [])
    expect(result.metadata).to eq(provider_attempts: 1, token_generations: 1, provider_request_id: 'query-from-body-1')
    expect(a_request(:post, companies_url).with { |req| req.headers.key?('Authorization') }).not_to have_been_made
    expect(a_request(:post, companies_url).with { |req| req.body.include?(credentials[:password]) }).not_to have_been_made
  end

  it 'lê só BIGDATACORP_USER e BIGDATACORP_PASSWORD do ambiente, pela configuração da plataforma' do
    stub_request(:post, token_url).to_return(token_response('access-1', 'token-id-1'))
    stub_request(:post, companies_url).to_return(json_response({ Result: [] }))

    with_modified_env(BIGDATACORP_USER: 'fixture-env-user', BIGDATACORP_PASSWORD: 'fixture-env-password', UNRELATED_SECRET: 'must-not-be-read') do
      described_class.new(sleeper: ->(_) {}, logger: logger).search_companies(query: 'name{Acme}')
    end

    expect(a_request(:post, token_url).with(body: { login: 'fixture-env-user', password: 'fixture-env-password', expires: 1 }.to_json))
      .to have_been_made.once
    expect(a_request(:post, token_url).with { |req| req.body.include?('must-not-be-read') }).not_to have_been_made
  end

  it 'sem credencial levanta BIGDATACORP_NOT_CONFIGURED sem nenhuma chamada HTTP' do
    with_modified_env(BIGDATACORP_USER: nil, BIGDATACORP_PASSWORD: nil) do
      expect(described_class.configured?).to be(false)
      error = captured_error { described_class.new(logger: logger).search_companies(query: 'name{Acme}') }

      expect(error.code).to eq('BIGDATACORP_NOT_CONFIGURED')
      expect(error.phase).to eq(:configuration)
    end
    expect(a_request(:any, /bigdatacorp/)).not_to have_been_made
  end

  it 'reaproveita o token em memória até expirar' do
    now = 1_000.0
    timed_client = build_client(clock: -> { now }, token_ttl: 60)
    stub_request(:post, token_url).to_return(token_response('access-1', 'token-id-1'), token_response('access-2', 'token-id-2'))
    stub_request(:post, companies_url).to_return(json_response({ Result: [] }))

    timed_client.search_companies(query: 'name{One}')
    timed_client.search_companies(query: 'name{Two}')
    expect(a_request(:post, token_url)).to have_been_made.once

    now += 60.001
    timed_client.search_companies(query: 'name{Three}')
    expect(a_request(:post, token_url)).to have_been_made.twice
  end

  it 'gera credencial de novo uma vez depois de 401 e não entra em laço no segundo 401' do
    stub_request(:post, token_url).to_return(token_response('access-1', 'token-id-1'), token_response('access-2', 'token-id-2'))
    stub_request(:post, companies_url).to_return(json_response({ error: 'expired' }, 401), json_response({ error: 'still' }, 401))

    error = captured_error { search }

    expect(error).to have_attributes(code: 'BIGDATACORP_HTTP_ERROR', status: 401, provider_attempts: 2)
    expect(a_request(:post, token_url)).to have_been_made.twice
  end

  it 'não reenvia a consulta paga depois de timeout e devolve BIGDATACORP_TIMEOUT' do
    stub_request(:post, token_url).to_return(token_response)
    stub_request(:post, companies_url).to_timeout.then.to_return(json_response({ QueryId: 'must-not-run', Result: [] }))

    error = captured_error { build_client(max_provider_attempts: 4).search_companies(query: 'name{Acme}') }

    expect(error).to have_attributes(code: 'BIGDATACORP_TIMEOUT', phase: :provider, provider_attempts: 1)
    expect(a_request(:post, companies_url)).to have_been_made.once
    expect(sleeps).to be_empty
  end

  it 'falha de rede depois do envio vira BIGDATACORP_DELIVERY_UNKNOWN e nunca reenvia' do
    stub_request(:post, token_url).to_return(token_response)
    stub_request(:post, companies_url).to_raise(Errno::ECONNRESET).then.to_return(json_response({ Result: [] }))

    error = captured_error { search }

    expect(error).to have_attributes(code: 'BIGDATACORP_DELIVERY_UNKNOWN', provider_attempts: 1)
    expect(a_request(:post, companies_url)).to have_been_made.once
  end

  it 'corpo de sucesso que não é JSON vira BIGDATACORP_DELIVERY_UNKNOWN' do
    stub_request(:post, token_url).to_return(token_response)
    stub_request(:post, companies_url).to_return(status: 200, body: '<html>oops</html>')

    expect(captured_error { search }).to have_attributes(code: 'BIGDATACORP_DELIVERY_UNKNOWN', status: 200, provider_attempts: 1)
  end

  it 'repete 429 e 5xx explícitos com espera crescente' do
    stub_request(:post, token_url).to_return(token_response)
    stub_request(:post, companies_url).to_return(json_response({ error: 'rate' }, 429), json_response({ error: 'down' }, 503),
                                                 json_response({ QueryId: 'query-retried', Result: [] }))

    result = search

    expect(result.metadata).to include(provider_attempts: 3, provider_request_id: 'query-retried')
    expect(sleeps).to eq([0.25, 0.5])
  end

  it 'erro 5xx na última tentativa vira BIGDATACORP_HTTP_ERROR com o status' do
    stub_request(:post, token_url).to_return(token_response)
    stub_request(:post, companies_url).to_return(json_response({ error: 'down' }, 503))

    expect(captured_error { search }).to have_attributes(code: 'BIGDATACORP_HTTP_ERROR', status: 503, provider_attempts: 3)
  end

  it 'pode repetir o timeout do token, porque gerar token não é a consulta paga' do
    stub_request(:post, token_url).to_timeout.then.to_return(token_response)
    stub_request(:post, companies_url).to_return(json_response({ QueryId: 'query-after-token-retry', Result: [] }))

    result = build_client(max_token_attempts: 2).search_companies(query: 'name{Acme}')

    expect(result.metadata).to include(provider_attempts: 1, token_generations: 1, provider_request_id: 'query-after-token-retry')
    expect(sleeps).to eq([0.25])
  end

  it 'timeout em todas as tentativas do token vira BIGDATACORP_TOKEN_UNAVAILABLE sem consulta paga' do
    stub_request(:post, token_url).to_timeout

    error = captured_error { search }

    expect(error).to have_attributes(code: 'BIGDATACORP_TOKEN_UNAVAILABLE', phase: :token, provider_attempts: 0)
    expect(a_request(:post, companies_url)).not_to have_been_made
  end

  it 'não repete 4xx permanente diferente de 401' do
    stub_request(:post, token_url).to_return(token_response)
    stub_request(:post, companies_url).to_return(json_response({ error: 'invalid query' }, 400))

    expect(captured_error { search }).to have_attributes(code: 'BIGDATACORP_HTTP_ERROR', status: 400, provider_attempts: 1)
    expect(sleeps).to be_empty
  end

  it 'não segue redirecionamento' do
    stub_request(:post, token_url).to_return(token_response)
    stub_request(:post, companies_url).to_return(status: 302, headers: { 'Location' => 'https://evil.example/empresas' })

    expect(captured_error { search }).to have_attributes(code: 'BIGDATACORP_HTTP_ERROR', status: 302)
    expect(a_request(:any, 'https://evil.example/empresas')).not_to have_been_made
  end

  it 'resposta de token sem token e tokenID vira BIGDATACORP_TOKEN_INVALID_RESPONSE' do
    stub_request(:post, token_url).to_return(json_response({ token: 'only-access' }))

    expect(captured_error { search }).to have_attributes(code: 'BIGDATACORP_TOKEN_INVALID_RESPONSE', phase: :token)
    expect(a_request(:post, companies_url)).not_to have_been_made
  end

  it 'não põe credencial, token nem corpo do fornecedor em erro, log ou inspect' do
    stub_request(:post, token_url).to_return(json_response({ token: 'fixture-access-secret', tokenID: 'fixture-token-id-secret',
                                                             payload: 'provider-private-payload' }, 503))

    error = captured_error { build_client(max_token_attempts: 1).search_companies(query: 'name{Acme}') }
    evidence = [error.message, error.inspect, error.full_message, log_lines.join("\n"), client.inspect, client.to_s].join("\n")

    expect(error.code).to eq('BIGDATACORP_TOKEN_UNAVAILABLE')
    [credentials[:username], credentials[:password], 'fixture-access-secret', 'fixture-token-id-secret',
     'provider-private-payload'].each { |secret| expect(evidence).not_to include(secret) }
  end

  it 'não expõe o token em cache no inspect depois de uma consulta' do
    stub_request(:post, token_url).to_return(token_response)
    stub_request(:post, companies_url).to_return(json_response({ Result: [] }))

    search

    [client.inspect, client.to_s, client.instance_variables.map { |name| client.instance_variable_get(name).inspect }.join].each do |text|
      expect(text).not_to include('fixture-access-secret', 'fixture-token-id-secret', credentials[:password])
    end
  end
end
