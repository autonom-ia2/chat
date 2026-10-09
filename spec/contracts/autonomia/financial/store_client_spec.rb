require_relative 'store_spec_helper'

RSpec.describe Autonomia::Financial::StoreClient do
  let(:fixtures) { JSON.parse(File.read(File.expand_path('../../../fixtures/autonomia_store/contracts.v1.json', __dir__))) }
  let(:base_url) { 'https://financial.example.test' }
  let(:client_options) do
    { authorization_token: 'oauth-access-example', installation_api_key: 'scoped-key-example',
      namespace: fixtures.fetch('namespace'), buyer_subject: 'buyer-test-1', base_url: base_url }
  end
  let(:client) { described_class.new(**client_options) }
  let(:reserve_payload) { fixtures.fetch('reserveRequest') }
  let(:reservation_response) { fixtures.fetch('reservationResponse') }
  let(:reservation_id) { reservation_response.fetch('reservation').fetch('id') }
  let(:reservation_url) { "#{base_url}/financial/internal/usage-reservations" }

  it 'uses OAuth bearer and scoped machine credentials, not Chatwoot session headers' do
    stub = stub_request(:get, "#{base_url}/financial/internal/store/catalog?page=1&pageSize=20")
           .with do |request|
      request.headers['Authorization'] == 'Bearer oauth-access-example' && request.headers['X-Api-Key'] == 'scoped-key-example' &&
        %w[Access-Token Client Uid].none? { |header| request.headers.key?(header) }
    end.to_return(status: 200, body: fixtures.fetch('catalog').to_json)

    expect(client.catalog!).to eq(fixtures.fetch('catalog'))
    expect(stub).to have_been_requested.once
  end

  it 'reads the service contract for the authenticated buyer' do
    subscription = fixtures.fetch('serviceSubscription')
    stub_request(:get, "#{base_url}/financial/internal/store/service-subscriptions/#{subscription['id']}")
      .to_return(status: 200, body: subscription.to_json)
    expect(client.service_subscription!(subscription['id'])).to eq(subscription)
  end

  it 'rejects another buyer service contract' do
    subscription = fixtures.fetch('serviceSubscription')
    subscription['buyer']['cognitoSub'] = 'another-buyer'
    stub_request(:get, "#{base_url}/financial/internal/store/service-subscriptions/#{subscription['id']}")
      .to_return(status: 200, body: subscription.to_json)
    expect { client.service_subscription!(subscription['id']) }.to raise_error(Autonomia::Financial::StoreClientError) { |e|
      expect(e.code).to eq('RESPONSE_TARGET_MISMATCH')
    }
  end

  it 'preserves a Financial access denial even for an active subscription' do
    subscription = fixtures.fetch('serviceSubscription')
    subscription['access']['allowed'] = false
    stub_request(:get, "#{base_url}/financial/internal/store/service-subscriptions/#{subscription['id']}")
      .to_return(status: 200, body: subscription.to_json)
    expect(client.service_subscription!(subscription['id']).dig('access', 'allowed')).to be(false)
  end

  it 'rejects a catalog from another installation or product' do
    fixtures['catalog']['namespace']['installationId'] = 'agents-test'
    stub_request(:get, "#{base_url}/financial/internal/store/catalog?page=1&pageSize=20")
      .to_return(status: 200, body: fixtures.fetch('catalog').to_json)
    expect { client.catalog! }.to raise_error(Autonomia::Financial::StoreClientError) { |e|
      expect(e.code).to eq('RESPONSE_SCOPE_MISMATCH')
    }
  end

  it 'does not convert a store 404 into absence of a subscription' do
    stub_request(:get, "#{base_url}/financial/internal/store/catalog?page=1&pageSize=20")
      .to_return(status: 404, body: '{}')
    expect { client.catalog! }.to raise_error(Autonomia::Financial::StoreClientError) { |e| expect(e.status).to eq(404) }
  end

  it 'rejects a principal from another installation even within a valid catalog namespace' do
    fixtures['catalog']['data'][0]['target']['installationId'] = 'agents-test'
    stub_request(:get, "#{base_url}/financial/internal/store/catalog?page=1&pageSize=20")
      .to_return(status: 200, body: fixtures.fetch('catalog').to_json)
    expect { client.catalog! }.to raise_error(Autonomia::Financial::StoreClientError) { |e|
      expect(e.code).to eq('RESPONSE_SCOPE_MISMATCH')
    }
  end

  it 'rejects a response from another product in the same installation' do
    fixtures['catalog']['namespace']['productCatalogItemId'] = '10000000-0000-4000-8000-000000000002'
    stub_request(:get, "#{base_url}/financial/internal/store/catalog?page=1&pageSize=20")
      .to_return(status: 200, body: fixtures.fetch('catalog').to_json)
    expect { client.catalog! }.to raise_error(Autonomia::Financial::StoreClientError) { |e|
      expect(e.code).to eq('RESPONSE_SCOPE_MISMATCH')
    }
  end

  it 'passes an unchanged stable checkout intention without activating resources' do
    stub = stub_request(:post, "#{base_url}/financial/internal/store/checkout-sessions")
           .with(headers: { 'Idempotency-Key' => 'checkout:test:1', 'Content-Type' => 'application/json' },
                 body: fixtures.fetch('checkoutRequest').to_json)
           .to_return(status: 201, body: fixtures.fetch('checkoutResponse').to_json)
    expect(client.checkout!(fixtures.fetch('checkoutRequest'), idempotency_key: 'checkout:test:1')).to eq(fixtures.fetch('checkoutResponse'))
    expect(stub).to have_been_requested.once
  end

  it 'repeats exactly the same reservation payload on a caller-initiated retry' do
    stub = stub_request(:post, reservation_url).with(body: reserve_payload.to_json)
           .to_return(status: 201, body: reservation_response.to_json)
           .then.to_return(status: 200, body: reservation_response.merge('replayed' => true).to_json)
    expect(client.reserve!(reserve_payload)['replayed']).to be(false)
    expect(client.reserve!(reserve_payload)['replayed']).to be(true)
    expect(stub).to have_been_requested.twice
  end

  it 'does not automatically retry or release after an ambiguous write timeout' do
    stub = stub_request(:post, reservation_url).to_timeout
    expect { client.reserve!(reserve_payload) }.to raise_error(Autonomia::Financial::StoreClientError) { |e|
      expect(e.outcome).to eq('unknown')
    }
    expect(stub).to have_been_requested.once
    expect(WebMock).not_to have_requested(:post, /release/)
  end

  it 'keeps server errors and malformed successful writes as unknown outcomes' do
    stub_request(:post, reservation_url).to_return(status: 503, body: '{}')
    expect { client.reserve!(reserve_payload) }.to raise_error(Autonomia::Financial::StoreClientError) { |e|
      expect(e.outcome).to eq('unknown')
    }
    stub_request(:post, reservation_url).to_return(status: 200, body: 'not-json')
    expect { client.reserve!(reserve_payload) }.to raise_error(Autonomia::Financial::StoreClientError) { |e|
      expect(e.code).to eq('INVALID_RESPONSE')
      expect(e.outcome).to eq('unknown')
    }
  end

  it 'rejects wrong resource responses without treating them as a failed reservation' do
    reservation_response['reservation']['resourceRef']['id'] = '99'
    stub_request(:post, reservation_url).to_return(status: 201, body: reservation_response.to_json)
    expect { client.reserve!(reserve_payload) }.to raise_error(Autonomia::Financial::StoreClientError) { |e|
      expect(e.code).to eq('RESPONSE_TARGET_MISMATCH')
      expect(e.outcome).to eq('unknown')
    }
  end

  it 'preserves safe conflict codes but never upstream messages or credentials' do
    body = { error: { code: 'IDEMPOTENCY_CONFLICT', message: 'sensitive-response' }, token: 'sensitive-token' }
    stub_request(:post, reservation_url).to_return(status: 409, body: body.to_json)
    expect { client.reserve!(reserve_payload) }.to raise_error(Autonomia::Financial::StoreClientError) { |e|
      expect(e.payload).to eq('code' => 'IDEMPOTENCY_CONFLICT', 'outcome' => 'failure')
      expect(e.message).to eq('Financial store request failed.')
      expect(e.status).to eq(409)
    }
  end

  it 'can read the same reservation when recovering an unknown outcome' do
    stub_request(:get, "#{reservation_url}/#{reservation_id}").to_return(status: 200, body: reservation_response.to_json)
    expect(client.reservation!(reservation_id)).to eq(reservation_response)
  end

  it 'commits and releases the original reservation without creating another one' do
    committed = JSON.parse(reservation_response.to_json)
    committed['reservation'].merge!('status' => 'committed', 'expiresAt' => nil)
    stub_request(:post, "#{reservation_url}/#{reservation_id}/commit").with(body: { idempotencyKey: 'commit:test:1' }.to_json)
      .to_return(status: 200, body: committed.to_json)
    expect(client.commit!(reservation_id, 'idempotencyKey' => 'commit:test:1')).to eq(committed)
    released = JSON.parse(committed.to_json)
    released['reservation']['status'] = 'released'
    payload = { 'idempotencyKey' => 'release:test:1', 'reason' => 'resource_disabled' }
    stub_request(:post, "#{reservation_url}/#{reservation_id}/release").with(body: payload.to_json)
      .to_return(status: 200, body: released.to_json)
    expect(client.release!(reservation_id, payload)).to eq(released)
    expect(WebMock).not_to have_requested(:post, reservation_url)
  end

  it 'rejects traversal IDs and invalid quantities before sending HTTP' do
    expect { client.reservation!('../other') }.to raise_error(Autonomia::Financial::StoreContractError)
    expect { client.reserve!(reserve_payload.merge('quantity' => '1')) }.to raise_error(Autonomia::Financial::StoreContractError)
    expect(WebMock).not_to have_requested(:any, /financial.example.test/)
  end

  it 'rejects a non-HTTPS origin and missing credentials without leaking their values' do
    expect { described_class.new(**client_options.merge(base_url: 'http://financial.example.test')) }
      .to raise_error(ArgumentError, 'Financial store requires an HTTPS origin.')
    expect { described_class.new(**client_options.merge(installation_api_key: '')) }
      .to raise_error(ArgumentError, 'Financial credentials are required.')
  end

  it 'rejects idempotency keys containing header control characters before sending HTTP' do
    expect { client.checkout!(fixtures.fetch('checkoutRequest'), idempotency_key: "intent\r\nX-Evil: value") }
      .to raise_error(Autonomia::Financial::StoreContractError)
    expect(WebMock).not_to have_requested(:any, /financial.example.test/)
  end

  it 'treats a read timeout as a read failure, not evidence that a reservation was released' do
    stub_request(:get, "#{reservation_url}/#{reservation_id}").to_timeout
    expect { client.reservation!(reservation_id) }.to raise_error(Autonomia::Financial::StoreClientError) { |e|
      expect(e.outcome).to eq('failure')
    }
    expect(WebMock).not_to have_requested(:post, /financial.example.test/)
  end
end
