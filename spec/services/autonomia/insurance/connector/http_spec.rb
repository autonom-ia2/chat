require 'rails_helper'

RSpec.describe Autonomia::Insurance::Connector::Http do
  let(:invoke_url) { 'https://lambda.us-east-1.amazonaws.com/2015-03-31/functions/adapters-test/invocations' }
  let(:credentials) { { provider: 'agger', username: 'c@x.com', password: 'segredo' } }
  # Depois de aberta a sessão, TODA operação viaja com ela — nunca com a credencial.
  let(:with_session) { { provider: 'agger', session: { 'multicalculoToken' => 'multi' } } }

  before do
    stub_const('ENV', ENV.to_h.merge('INSURANCE_CONNECTOR_FUNCTION' => 'adapters-test', 'AWS_REGION' => 'us-east-1'))
    # A assinatura SigV4 usa a credencial da instância; no teste basta uma credencial estática.
    allow(Aws::InstanceProfileCredentials).to receive(:new)
      .and_return(Aws::Credentials.new('AKIAEXEMPLO', 'segredo-de-assinatura'))
  end

  # A invocação sempre devolve 200; o status de negócio vem em `statusCode` dentro do corpo.
  def stub_invoke(inner_status:, inner_body:, outer_status: 200, outer_body: nil)
    body = outer_body || { 'statusCode' => inner_status, 'body' => inner_body }.to_json
    stub_request(:post, invoke_url)
      .to_return(status: outer_status, body: body, headers: { 'Content-Type' => 'application/json' })
  end

  # O TESTE QUE FALTAVA. O adapter é TypeScript e devolve camelCase; o Rails inteiro lê snake_case.
  # Ninguém exercitava essa fronteira: o `Mock` já nasce em snake_case (ele SUBSTITUI o Http, não
  # passa por ele), então toda a suíte passava verde validando a minha suposição do formato contra
  # ela mesma. O formato REAL do Lambda nunca era exercido em teste nenhum.
  #
  # O preço disso: `expiresAt` chegava, `payload['expires_at']` lia nil, `session_live?` era sempre
  # falso, e a sessão única nunca reusou nada em produção.
  describe 'camelCase do adapter na fronteira' do
    it 'traduz o prazo da sessão, que é o campo que decide se ela vale' do
      # Arrange — payload EXATO do adapter (core/adapter.ts: OpenSession)
      prazo = 3.hours.from_now.utc.iso8601
      stub_invoke(inner_status: 200, inner_body: {
        'platform' => 'agger',
        'data' => { 'aggregatorToken' => 'agg', 'multicalculoToken' => 'multi' },
        'expiresAt' => prazo,
        'accountLabel' => 'CORRETORA X',
        'droppedPreviousSession' => false
      }.to_json)

      # Act
      payload = described_class.new.open_session(**credentials)

      # Assert
      expect(payload['expires_at']).to eq(prazo)
      expect(payload['account_label']).to eq('CORRETORA X')
      expect(payload['dropped_previous_session']).to be(false)
      expect(payload.keys).not_to include('expiresAt', 'accountLabel', 'droppedPreviousSession')
    end

    it 'traduz o prazo que vem no status da conexão' do
      # Arrange — ConnectionState usa OUTRO nome para o mesmo conceito
      prazo = 2.hours.from_now.utc.iso8601
      stub_invoke(inner_status: 200, inner_body: {
        'platform' => 'agger', 'status' => 'ready',
        'sessionExpiresAt' => prazo, 'accountLabel' => 'CORRETORA X',
        'checkedAt' => Time.current.utc.iso8601
      }.to_json)

      # Act
      payload = described_class.new.connection_status(**with_session)

      # Assert
      expect(payload['session_expires_at']).to eq(prazo)
      expect(payload['checked_at']).to be_present
    end

    it 'não mexe em `data`, que é a sessão opaca do portal' do
      # Arrange — as chaves de dentro de `data` são do adapter; traduzi-las quebraria o token
      stub_invoke(inner_status: 200, inner_body: {
        'platform' => 'agger',
        'data' => { 'aggregatorToken' => 'agg', 'multicalculoToken' => 'multi' },
        'expiresAt' => 1.hour.from_now.utc.iso8601
      }.to_json)

      # Act / Assert
      expect(described_class.new.open_session(**credentials)['data'])
        .to eq({ 'aggregatorToken' => 'agg', 'multicalculoToken' => 'multi' })
    end

    it 'deixa passar o payload que já vem em snake_case' do
      # Arrange — retrocompatibilidade: adapter antigo, ou o dia em que ele passar a mandar assim
      prazo = 1.hour.from_now.utc.iso8601
      stub_invoke(inner_status: 200,
                  inner_body: { 'platform' => 'agger', 'expires_at' => prazo }.to_json)

      # Act / Assert
      expect(described_class.new.open_session(**credentials)['expires_at']).to eq(prazo)
    end
  end

  it 'signs the invocation, sends the open session in the event and returns the payload' do
    stub_invoke(inner_status: 200, inner_body: { 'status' => 'ready', 'account_label' => 'CORRETORA X' }.to_json)

    expect(described_class.new.connection_status(**with_session)).to include('status' => 'ready')
    expect(
      a_request(:post, invoke_url).with(
        headers: { 'Authorization' => %r{AWS4-HMAC-SHA256 Credential=AKIAEXEMPLO/.*lambda/aws4_request} }
      ) do |request|
        event = JSON.parse(request.body)
        event['rawPath'] == '/v1/agger/connection' &&
          JSON.parse(event['body']) == { 'session' => { 'multicalculoToken' => 'multi' } }
      end
    ).to have_been_made
  end

  # A credencial só existe no caminho que ABRE a sessão. Se ela vazasse para as demais operações, o
  # adapter abriria uma sessão nova a cada chamada e invalidaria a que está cotando.
  it 'sends the credentials only when opening a session' do
    stub_invoke(inner_status: 200, inner_body: { 'platform' => 'agger', 'data' => { 'token' => 'x' } }.to_json)

    expect(described_class.new.open_session(**credentials)).to include('platform' => 'agger')
    expect(
      a_request(:post, invoke_url) do |request|
        event = JSON.parse(request.body)
        event['rawPath'] == '/v1/agger/session' &&
          JSON.parse(event['body']) == { 'username' => 'c@x.com', 'password' => 'segredo' }
      end
    ).to have_been_made
  end

  it 'maps the inner status to the connector error kind' do
    { 401 => :auth_required, 422 => :validation, 502 => :unavailable, 504 => :timeout, 500 => :protocol }
      .each do |code, kind|
        stub_invoke(inner_status: code, inner_body: { 'error' => 'x' }.to_json)
        expect { described_class.new.connection_status(**with_session) }
          .to raise_error(an_object_having_attributes(kind: kind))
      end
  end

  it 'treats a lambda runtime failure as unavailable' do
    stub_invoke(inner_status: 200, inner_body: '{}', outer_body: { 'errorType' => 'Runtime.ExitError' }.to_json)

    expect { described_class.new.connection_status(**with_session) }
      .to raise_error(an_object_having_attributes(kind: :unavailable))
  end

  it 'treats a non-JSON success body as protocol so the ladder can step down' do
    stub_invoke(inner_status: 200, inner_body: '<html>manutencao</html>')

    expect { described_class.new.connection_status(**with_session) }
      .to raise_error(an_object_having_attributes(kind: :protocol))
  end

  it 'fails as config when the function name is missing' do
    stub_const('ENV', ENV.to_h.except('INSURANCE_CONNECTOR_FUNCTION'))

    expect { described_class.new.connection_status(**with_session) }
      .to raise_error(an_object_having_attributes(kind: :config))
  end

  it 'never leaks the signed request or the password in the error message' do
    stub_request(:post, invoke_url).to_raise(SocketError.new('falhou com X-Amz-Signature=abc e senha segredo'))

    expect { described_class.new.connection_status(**with_session) }
      .to raise_error(an_object_having_attributes(kind: :unavailable)) do |error|
        expect(error.message).not_to include('X-Amz-Signature')
        expect(error.message).not_to include('segredo')
      end
  end
end
