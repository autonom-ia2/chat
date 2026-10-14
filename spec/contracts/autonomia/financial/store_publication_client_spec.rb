# frozen_string_literal: true

require_relative 'store_spec_helper'
require_relative '../../../../app/services/autonomia/financial/store_configuration'
require_relative '../../../../app/services/autonomia/financial/store_identity'
require_relative '../../../../app/services/autonomia/financial/store_features'
require_relative '../../../../app/services/autonomia/financial/store_actor_assertion'
require_relative '../../../../app/services/autonomia/financial/store_publication_contract'
require_relative '../../../../app/services/autonomia/financial/store_publication_client'

RSpec.describe Autonomia::Financial::StorePublicationClient do
  let(:env) do
    { 'FINANCIAL_STORE_API_KEY' => 'scoped-example-key', 'FINANCIAL_STORE_ACTOR_ASSERTION_SECRET' => 'example-only-not-a-real-secret-32bytes',
      'FINANCIAL_STORE_INSTALLATION_ID' => 'chat2you-test', 'FINANCIAL_STORE_PRODUCT_CATALOG_ITEM_ID' => '10000000-0000-4000-8000-000000000001',
      'AUTONOMIA_FINANCIAL_API_BASE_URL' => 'https://financial.example.test' }
  end
  let(:configuration) { Autonomia::Financial::StoreConfiguration.new(env) }
  let(:client) { described_class.new(configuration: configuration, subject: 'cognito-example-sub', authorization_token: 'access-example') }
  let(:service_id) { '20000000-0000-4000-8000-000000000001' }
  let(:service) do
    { 'id' => service_id, 'key' => 'agent-test', 'name' => 'Example agent', 'description' => nil, 'logoUrl' => nil, 'status' => 'inactive' }
  end
  let(:target) { { 'type' => 'agent', 'installationId' => 'chat2you-test', 'principalAgentId' => 10 } }
  let(:publication) { { 'serviceCatalogItemId' => service_id, 'group' => 'agent', 'target' => target, 'status' => 'active', 'displayOrder' => 0 } }
  let(:envelope) { { 'contractVersion' => 1, 'namespace' => configuration.namespace } }

  it 'signs the verified actor and principal filter, without session headers' do
    captured = nil
    stub_request(:get, 'https://financial.example.test/financial/internal/store/services?principalAgentId=10').with do |request|
      captured = JWT.decode(request.headers.fetch('X-Store-Actor-Assertion'), configuration.assertion_secret, true, algorithm: 'HS256').first
      request.headers['Authorization'] == 'Bearer access-example' && request.headers['X-Api-Key'] == configuration.api_key
    end.to_return(status: 200, body: envelope.merge('data' => [service]).to_json)
    expect(client.agent_services!(10).fetch('data')).to eq([service])
    expect(captured).to include('sub' => 'cognito-example-sub', 'role' => 'superadmin', 'principalAgentId' => 10,
                                'action' => 'service.read', 'aud' => 'financial-internal-store', 'bodySha256' => Digest::SHA256.hexdigest(''))
    expect(captured['exp'] - captured['iat']).to eq(120)
  end

  it 'binds a fresh assertion to the exact bytes of each mutation and preserves idempotency intent' do
    assertions = []
    payload = { 'name' => 'Example agent', 'group' => 'agent', 'target' => target, 'idempotencyKey' => 'draft-test-intent-1' }
    stub_request(:post, 'https://financial.example.test/financial/internal/store/services').with do |request|
      claims = JWT.decode(request.headers.fetch('X-Store-Actor-Assertion'), configuration.assertion_secret, true, algorithm: 'HS256').first
      assertions << claims['jti']
      claims['bodySha256'] == Digest::SHA256.hexdigest(request.body) && claims['action'] == 'service.create' && JSON.parse(request.body) == payload
    end.to_return(status: 201, body: envelope.merge('service' => service).to_json)
    2.times { expect(client.create_service!(payload).fetch('service')).to eq(service) }
    expect(assertions.uniq.size).to eq(2)
  end

  it 'signs the closed feature filter without claiming an agent' do
    stub_request(:get, 'https://financial.example.test/financial/internal/store/services?featureKey=prospecting').with do |request|
      claims = JWT.decode(request.headers.fetch('X-Store-Actor-Assertion'), configuration.assertion_secret, true, algorithm: 'HS256').first
      claims['featureKey'] == 'prospecting' && !claims.key?('principalAgentId')
    end.to_return(status: 200, body: envelope.merge('data' => [service]).to_json)
    expect(client.feature_services!('prospecting').fetch('data')).to eq([service])
  end

  it 'rejects an unknown feature before issuing any HTTP request' do
    expect { client.feature_services!('arbitrary_feature') }.to raise_error(Autonomia::Financial::StoreClientError) do |error|
      expect(error.status).to eq(403)
    end
  end

  it 'rejects mismatched groups, arbitrary draft fields, and invalid order before HTTP' do
    payload = { 'name' => 'Example', 'group' => 'feature', 'target' => target, 'idempotencyKey' => 'draft-test-intent-1' }
    expect { client.create_service!(payload) }.to raise_error(Autonomia::Financial::StoreContractError)
    expect { client.create_service!(payload.merge('group' => 'agent', 'operatorId' => 'foreign')) }
      .to raise_error(Autonomia::Financial::StoreContractError)
    expect { client.publish!(service_id, publication.except('serviceCatalogItemId').merge('displayOrder' => 1_000_001)) }
      .to raise_error(Autonomia::Financial::StoreContractError)
  end

  it 'rejects wrong namespace in the managed services response' do
    stub_request(:get, 'https://financial.example.test/financial/internal/store/services?principalAgentId=10')
      .to_return(status: 200, body: envelope.merge('data' => [], 'namespace' => configuration.namespace.merge('installationId' => 'foreign')).to_json)
    expect { client.agent_services!(10) }.to raise_error(Autonomia::Financial::StoreClientError)
  end

  it 'uses PUT for publication and verifies the returned service and target' do
    payload = publication.except('serviceCatalogItemId')
    stub_request(:put, "https://financial.example.test/financial/internal/store/publications/#{service_id}")
      .to_return(status: 200, body: envelope.merge('publication' => publication, 'service' => service).to_json)
    expect(client.publish!(service_id, payload).fetch('publication')).to eq(publication)
  end

  it 'rejects an agent in another installation before issuing an HTTP request' do
    payload = { 'name' => 'Example', 'group' => 'agent', 'target' => target.merge('installationId' => 'other'),
                'idempotencyKey' => 'draft-example-intent' }
    expect { client.create_service!(payload) }.to raise_error(Autonomia::Financial::StoreClientError) { |error| expect(error.status).to eq(403) }
  end

  it 'rejects a publication response with a different principal' do
    wrong = publication.merge('target' => target.merge('principalAgentId' => 99))
    stub_request(:get, "https://financial.example.test/financial/internal/store/publications/#{service_id}")
      .to_return(status: 200, body: envelope.merge('publication' => wrong, 'service' => service).to_json)
    expect { client.publication!(service_id, target: target) }.to raise_error(Autonomia::Financial::StoreClientError)
  end

  it 'reports an uncertain outcome on a publication timeout' do
    stub_request(:put, "https://financial.example.test/financial/internal/store/publications/#{service_id}").to_timeout
    expect { client.publish!(service_id, publication.except('serviceCatalogItemId')) }
      .to raise_error(Autonomia::Financial::StoreClientError) { |error| expect(error.outcome).to eq('unknown') }
  end

  it 'sanitizes upstream errors rather than exposing tokens or response bodies' do
    stub_request(:get, 'https://financial.example.test/financial/internal/store/services?principalAgentId=10')
      .to_return(status: 403, body: { error: { code: 'FORBIDDEN', message: 'sensitive upstream data' } }.to_json)
    expect { client.agent_services!(10) }.to raise_error(Autonomia::Financial::StoreClientError) do |error|
      expect(error.message).not_to include('sensitive')
      expect(error.code).to eq('FORBIDDEN')
    end
  end

  it 'refuses missing machine configuration or reuse of the API key as the assertion key' do
    expect { Autonomia::Financial::StoreConfiguration.new({}) }.to raise_error(Autonomia::Financial::StoreClientError)
    env['FINANCIAL_STORE_API_KEY'] = env['FINANCIAL_STORE_ACTOR_ASSERTION_SECRET']
    expect { configuration }.to raise_error(Autonomia::Financial::StoreClientError)
  end

  it 'gets the canonical Cognito subject from Identity, not the local/Auth UUID' do
    stub_request(:get, 'https://identity.example.test/me').with(headers: { 'Authorization' => 'Bearer access-example' })
                                                          .to_return(status: 200, body: { user: { id: 'auth-local-id',
                                                                                                  cognitoSub: 'cognito-example-sub' } }.to_json)
    expect(Autonomia::Financial::StoreIdentity.subject!('access-example', endpoint: 'https://identity.example.test/me')).to eq('cognito-example-sub')
  end

  it 'rejects missing canonical subject instead of falling back to the internal UUID' do
    stub_request(:get, 'https://identity.example.test/me').to_return(status: 200, body: { user: { id: 'auth-local-id' } }.to_json)
    expect { Autonomia::Financial::StoreIdentity.subject!('access-example', endpoint: 'https://identity.example.test/me') }
      .to raise_error(Autonomia::Financial::StoreClientError)
  end
end
