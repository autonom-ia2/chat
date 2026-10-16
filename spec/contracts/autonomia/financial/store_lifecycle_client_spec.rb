require_relative 'store_spec_helper'
require_relative '../../../../app/services/autonomia/financial/store_configuration'
require_relative '../../../../app/services/autonomia/financial/store_features'
require_relative '../../../../app/services/autonomia/financial/store_actor_assertion'
require_relative '../../../../app/services/autonomia/financial/store_publication_contract'
require_relative '../../../../app/services/autonomia/financial/store_publication_client'
require_relative '../../../../app/services/autonomia/financial/store_checkout_contract'
require_relative '../../../../app/services/autonomia/financial/store_checkout_client'
require_relative '../../../../app/services/autonomia/financial/store_lifecycle_contract'
require_relative '../../../../app/services/autonomia/financial/store_lifecycle_client'

RSpec.describe Autonomia::Financial::StoreLifecycleClient do
  let(:fixture) { JSON.parse(File.read(File.expand_path('../../../fixtures/autonomia_store/lifecycle.v1.json', __dir__))) }
  let(:capability) { fixture.fetch('cancellationCapability') }
  let(:id) { capability.dig('data', 'serviceSubscriptionId') }
  let(:configuration) do
    Autonomia::Financial::StoreConfiguration.new(
      'FINANCIAL_STORE_API_KEY' => 'example-scoped-key', 'FINANCIAL_STORE_ACTOR_ASSERTION_SECRET' => 'example-assertion-secret-not-real-32',
      'FINANCIAL_STORE_INSTALLATION_ID' => capability.dig('namespace', 'installationId'),
      'FINANCIAL_STORE_PRODUCT_CATALOG_ITEM_ID' => capability.dig('namespace', 'productCatalogItemId'),
      'AUTONOMIA_FINANCIAL_API_BASE_URL' => 'https://financial.example.test'
    )
  end
  let(:client) do
    described_class.new(configuration: configuration, subject: capability.dig('buyer', 'cognitoSub'), authorization_token: 'example-access')
  end
  let(:path) { "https://financial.example.test/financial/internal/store/service-subscriptions/#{id}/cancellation" }

  it 'validates all E4 fixtures without fetching remote schemas' do
    fixture.each { |name, value| expect(Autonomia::Financial::StoreLifecycleContract.validate!(name, value)).to eq(value) }
  end

  it 'reads a buyer-scoped capability with the specific cancellation assertion' do
    stub_request(:get, path).with do |request|
      claims = JWT.decode(request.headers.fetch('X-Store-Actor-Assertion'), configuration.assertion_secret, true, algorithm: 'HS256').first
      claims['action'] == 'subscription.cancellation.read' && claims['sub'] == capability.dig('buyer', 'cognitoSub')
    end.to_return(status: 200, body: capability.to_json)
    expect(client.cancellation!(id)).to eq(capability)
  end

  it 'binds the cancellation receipt to its original body, version and action' do
    request = fixture.fetch('cancellationCommandRequest')
    stub_request(:post, path).with(body: request.to_json).to_return(status: 200, body: fixture.fetch('cancellationCommandResponse').to_json)
    expect(client.schedule_cancellation!(id, request)).to eq(fixture['cancellationCommandResponse'])
    wrong = request.merge('idempotencyKey' => 'other-fictitious-intent')
    stub_request(:post, path).with(body: wrong.to_json).to_return(status: 200, body: fixture['cancellationCommandResponse'].to_json)
    expect { client.schedule_cancellation!(id, wrong) }.to raise_error(Autonomia::Financial::StoreClientError) { |e|
      expect(e.outcome).to eq('unknown')
    }
  end

  it 'never accepts another buyer or root as a capability' do
    data = capability.deep_dup
    data['buyer']['cognitoSub'] = 'another-fictitious-buyer'
    stub_request(:get, path).to_return(status: 200, body: data.to_json)
    expect { client.cancellation!(id) }.to raise_error(Autonomia::Financial::StoreClientError)
    data = capability.deep_dup
    data['data']['serviceSubscriptionId'] = '11111111-1111-4111-8111-111111111111'
    stub_request(:get, path).to_return(status: 200, body: data.to_json)
    expect { client.cancellation!(id) }.to raise_error(Autonomia::Financial::StoreClientError)
  end

  it 'rejects immediate policy, malformed version and browser attributes' do
    body = fixture.fetch('cancellationCommandRequest')
    [body.merge('policy' => 'immediate'), body.merge('expectedVersion' => '1'), body.merge('expectedVersion' => 0)].each do |wrong|
      expect { client.schedule_cancellation!(id, wrong) }.to raise_error(Autonomia::Financial::StoreContractError)
    end
  end

  it 'uses a separate action for reversing non-renewal, without guessing current version' do
    data = fixture.fetch('cancellationCommandResponse').deep_dup
    data['result']['type'] = 'subscription_renewal_resumed'
    data['data']['renewalState'] = 'renewing'
    stub_request(:post, "#{path}/resume").with do |request|
      claims = JWT.decode(request.headers.fetch('X-Store-Actor-Assertion'), configuration.assertion_secret, true, algorithm: 'HS256').first
      claims['action'] == 'subscription.cancellation.resume'
    end.to_return(status: 200, body: data.to_json)
    expect(client.resume_renewal!(id, fixture.fetch('cancellationCommandRequest'))).to eq(data)
  end

  it 'reconciles only the known session using its dedicated action, never a new checkout' do
    body = fixture.fetch('reconciliationRequest')
    response = fixture.fetch('reconciliationResponse')
    checkout_id = response.dig('operation', 'statusUrl').split('/').last
    url = "https://financial.example.test/financial/internal/store/checkout-sessions/#{checkout_id}/reconcile"
    stub_request(:post, url).with do |request|
      claims = JWT.decode(request.headers.fetch('X-Store-Actor-Assertion'), configuration.assertion_secret, true, algorithm: 'HS256').first
      claims['action'] == 'checkout.reconcile' && JSON.parse(request.body) == body
    end.to_return(status: 202, body: response.to_json)
    expect(client.reconcile_checkout!(checkout_id, body)).to eq(response)
    response['operation']['statusUrl'] = '/financial/internal/store/checkout-sessions/11111111-1111-4111-8111-111111111111'
    stub_request(:post, url).to_return(status: 200, body: response.to_json)
    expect { client.reconcile_checkout!(checkout_id, body) }.to raise_error(Autonomia::Financial::StoreClientError)
    expect(WebMock).not_to have_requested(:post, 'https://financial.example.test/financial/internal/store/checkout-sessions')
  end
end
