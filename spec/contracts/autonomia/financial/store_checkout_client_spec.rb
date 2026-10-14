require_relative 'store_spec_helper'
require_relative '../../../../app/services/autonomia/financial/store_configuration'
require_relative '../../../../app/services/autonomia/financial/store_features'
require_relative '../../../../app/services/autonomia/financial/store_actor_assertion'
require_relative '../../../../app/services/autonomia/financial/store_publication_contract'
require_relative '../../../../app/services/autonomia/financial/store_publication_client'
require_relative '../../../../app/services/autonomia/financial/store_checkout_contract'
require_relative '../../../../app/services/autonomia/financial/store_checkout_client'

RSpec.describe Autonomia::Financial::StoreCheckoutClient do
  let(:fixture) { JSON.parse(File.read(File.expand_path('../../../fixtures/autonomia_store/checkout.v1.json', __dir__))) }
  let(:context) { fixture['checkoutActorExtension']['returnContext'] }
  let(:configuration) do
    Autonomia::Financial::StoreConfiguration.new(
      'FINANCIAL_STORE_API_KEY' => 'example-scoped-key', 'FINANCIAL_STORE_ACTOR_ASSERTION_SECRET' => 'example-assertion-secret-not-real-32',
      'FINANCIAL_STORE_INSTALLATION_ID' => fixture['checkoutResponse']['namespace']['installationId'],
      'FINANCIAL_STORE_PRODUCT_CATALOG_ITEM_ID' => fixture['checkoutResponse']['namespace']['productCatalogItemId'],
      'AUTONOMIA_FINANCIAL_API_BASE_URL' => 'https://financial.example.test'
    )
  end
  let(:client) do
    described_class.new(configuration: configuration, subject: fixture['checkoutResponse']['buyer']['cognitoSub'],
                        authorization_token: 'example-access', checkout_context: context)
  end

  it 'binds price, caller, buyer, persisted intent, return context and idempotency header' do
    ids = []
    stub_request(:post, 'https://financial.example.test/financial/internal/store/checkout-sessions').with do |request|
      claims = JWT.decode(request.headers.fetch('X-Store-Actor-Assertion'), configuration.assertion_secret, true, algorithm: 'HS256').first
      ids << claims['jti']
      claims['checkoutIntentId'] == context['checkoutIntentId'] && claims['returnContext'] == context &&
        claims['featureKey'] == 'prospecting' && claims['action'] == 'checkout.create' &&
        claims['idempotencyKeySha256'] == Digest::SHA256.hexdigest(context['checkoutIntentId']) &&
        claims['bodySha256'] == Digest::SHA256.hexdigest(request.body)
    end.to_return(status: 201, body: fixture['checkoutResponse'].to_json)
    2.times { expect(client.checkout!(fixture['checkoutRequest'], idempotency_key: context['checkoutIntentId'])).to eq(fixture['checkoutResponse']) }
    expect(ids.uniq.size).to eq(2)
  end

  it 'recovers unknown checkout by reading the same intent, not creating another checkout' do
    stub_request(:post, 'https://financial.example.test/financial/internal/store/checkout-sessions/resolve')
      .with(body: { idempotencyKey: context['checkoutIntentId'] }.to_json)
      .to_return(status: 200, body: fixture['checkoutStatusResponse'].to_json)
    expect(client.resolve_checkout!(context['checkoutIntentId'], price_id: fixture['checkoutRequest']['servicePlanPriceId']))
      .to eq(fixture['checkoutStatusResponse'])
    expect(WebMock).not_to have_requested(:post, 'https://financial.example.test/financial/internal/store/checkout-sessions')
  end

  it 'rejects other buyers and intent/price mismatch before exposing the checkout URL' do
    fixture['checkoutResponse']['buyer']['cognitoSub'] = 'foreign'
    isolated = described_class.new(configuration: configuration, subject: 'original', authorization_token: 'example-access',
                                   checkout_context: context)
    stub_request(:post, 'https://financial.example.test/financial/internal/store/checkout-sessions')
      .to_return(status: 200, body: fixture['checkoutResponse'].to_json)
    expect { isolated.checkout!(fixture['checkoutRequest'], idempotency_key: context['checkoutIntentId']) }
      .to raise_error(Autonomia::Financial::StoreClientError) { |error| expect(error.outcome).to eq('unknown') }
  end

  it 'rejects checkout URLs outside the Financial origin or containing credentials' do
    fixture['checkoutResponse']['checkoutUrl'] = 'https://attacker.example.test/checkout'
    stub_request(:post, 'https://financial.example.test/financial/internal/store/checkout-sessions')
      .to_return(status: 200, body: fixture['checkoutResponse'].to_json)
    expect { client.checkout!(fixture['checkoutRequest'], idempotency_key: context['checkoutIntentId']) }
      .to raise_error(Autonomia::Financial::StoreClientError) { |error| expect(error.code).to eq('INVALID_CHECKOUT_URL') }
  end

  it 'reads historical service presentation without consulting the published catalog' do
    stub_request(:get, 'https://financial.example.test/financial/internal/store/service-subscriptions?page=1&pageSize=20')
      .to_return(status: 200, body: fixture['serviceSubscriptionListResponse'].to_json)
    expect(client.subscriptions!['data'].first['service']['name']).to eq('Prospecção piloto fictício')
  end

  it 'uses only the new scoped reservation paths, and does not accept a released commit' do
    id = fixture['reservationResponse']['reservation']['id']
    fixture['reservationResponse']['reservation']['status'] = 'released'
    stub_request(:post, "https://financial.example.test/financial/internal/store/usage-reservations/#{id}/commit")
      .to_return(status: 200, body: fixture['reservationResponse'].to_json)
    expect { client.commit!(id, fixture['commitRequest']) }.to raise_error(Autonomia::Financial::StoreClientError)
  end

  it 'correlates the complete entitlement snapshot with the requested service and resource' do
    stub_request(:post, 'https://financial.example.test/financial/internal/store/entitlements/resolve')
      .to_return(status: 200, body: fixture['entitlementsResponse'].to_json)
    expect(client.entitlements!(fixture['entitlementsResolveRequest'])).to eq(fixture['entitlementsResponse'])
    wrong = fixture['entitlementsResolveRequest'].merge('resourceRef' => { 'type' => 'chatwoot.account', 'id' => 'other' })
    expect { client.entitlements!(wrong) }.to raise_error(Autonomia::Financial::StoreClientError)
  end

  it 'signs the agent target while keeping Financial body and legacy feature claims unchanged' do
    target = { 'type' => 'agent', 'installationId' => configuration.namespace.fetch('installationId'), 'principalAgentId' => 7 }
    agent_client = described_class.new(configuration: configuration, subject: fixture['checkoutResponse']['buyer']['cognitoSub'],
                                       authorization_token: 'example-access', checkout_context: context, checkout_target: target)
    stub_request(:post, 'https://financial.example.test/financial/internal/store/checkout-sessions').with do |request|
      claims = JWT.decode(request.headers.fetch('X-Store-Actor-Assertion'), configuration.assertion_secret, true, algorithm: 'HS256').first
      claims['target'] == target && !claims.key?('featureKey') && claims['returnContext'] == context &&
        JSON.parse(request.body) == fixture['checkoutRequest']
    end.to_return(status: 201, body: fixture['checkoutResponse'].to_json)
    expect(agent_client.checkout!(fixture['checkoutRequest'], idempotency_key: context['checkoutIntentId'])).to eq(fixture['checkoutResponse'])
  end
end
