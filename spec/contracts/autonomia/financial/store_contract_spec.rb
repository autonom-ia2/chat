require_relative 'store_spec_helper'

RSpec.describe Autonomia::Financial::StoreContract do
  let(:fixtures) { JSON.parse(File.read(File.expand_path('../../../fixtures/autonomia_store/contracts.v1.json', __dir__))) }

  %w[namespace checkoutRequest checkoutResponse reserveRequest reservationResponse serviceSubscription storeEvent].each do |schema|
    it "accepts the shared #{schema} fixture" do
      expect(described_class.validate!(schema, fixtures.fetch(schema))).to eq(fixtures.fetch(schema))
    end
  end

  it 'accepts an empty catalog and missing commercial icon' do
    catalog = fixtures.fetch('catalog')
    catalog['data'][0]['service']['logoUrl'] = nil
    expect(described_class.validate!('catalogResponse', catalog)).to eq(catalog)
    catalog['data'] = []
    catalog['pagination'].merge!('totalItems' => 0, 'totalPages' => 0)
    expect(described_class.validate!('catalogResponse', catalog)).to eq(catalog)
  end

  it 'does not accept legacy product subscription alongside the independent service contract' do
    payload = fixtures.fetch('reserveRequest').merge('userSubscriptionId' => '10000000-0000-4000-8000-000000000001')
    expect { described_class.validate!('reserveRequest', payload) }.to raise_error(Autonomia::Financial::StoreContractError)
  end

  it 'rejects caller-supplied quotas or buyer identity' do
    payload = fixtures.fetch('reserveRequest').merge('includedQuantity' => 999, 'buyerUserId' => 'another-buyer')
    expect { described_class.validate!('reserveRequest', payload) }.to raise_error(Autonomia::Financial::StoreContractError)
  end

  it 'requires a positive numeric quantity and an explicit stable timestamp' do
    payload = fixtures.fetch('reserveRequest')
    payload['quantity'] = '1'
    expect { described_class.validate!('reserveRequest', payload) }.to raise_error(Autonomia::Financial::StoreContractError)
    payload['quantity'] = 0
    expect { described_class.validate!('reserveRequest', payload) }.to raise_error(Autonomia::Financial::StoreContractError)
    payload['quantity'] = 1
    payload.delete('occurredAt')
    expect { described_class.validate!('reserveRequest', payload) }.to raise_error(Autonomia::Financial::StoreContractError)
  end

  it 'rejects invalid timestamp and malformed namespace IDs' do
    expect { described_class.validate!('reserveRequest', fixtures.fetch('reserveRequest').merge('occurredAt' => 'yesterday')) }
      .to raise_error(Autonomia::Financial::StoreContractError)
    expect { described_class.validate!('namespace', fixtures.fetch('namespace').merge('productCatalogItemId' => '../other')) }
      .to raise_error(Autonomia::Financial::StoreContractError)
  end

  it 'rejects resetting allocation capacity monthly' do
    metric = fixtures.fetch('catalog').dig('data', 0, 'offers', 0, 'limits', 0)
    metric['resetPeriod'] = 'monthly'
    expect { described_class.validate!('metric', metric) }.to raise_error(Autonomia::Financial::StoreContractError)
  end

  it 'accepts periodic consumption for any configured metric' do
    metric = fixtures.fetch('catalog').dig('data', 0, 'offers', 0, 'limits', 0)
    metric.merge!('usageBehavior' => 'consumption', 'resetPeriod' => 'billing_period', 'metricKey' => 'tokens_used')
    expect(described_class.validate!('metric', metric)).to eq(metric)
  end

  it 'requires committed allocation not to expire' do
    payload = fixtures.fetch('reservationResponse')
    payload['reservation']['status'] = 'committed'
    expect { described_class.validate!('reservationResponse', payload) }.to raise_error(Autonomia::Financial::StoreContractError)
    payload['reservation']['expiresAt'] = nil
    expect(described_class.validate!('reservationResponse', payload)).to eq(payload)
  end

  [nil, 'not-a-date'].each do |expiry|
    it "rejects a provisional reservation with expiry #{expiry.inspect}" do
      payload = fixtures.fetch('reservationResponse')
      payload['reservation']['expiresAt'] = expiry
      expect { described_class.validate!('reservationResponse', payload) }.to raise_error(Autonomia::Financial::StoreContractError)
    end
  end

  %w[released expired].each do |status|
    it "allows a null expiry after a reservation is #{status}" do
      payload = fixtures.fetch('reservationResponse')
      payload['reservation'].merge!('status' => status, 'expiresAt' => nil)
      expect(described_class.validate!('reservationResponse', payload)).to eq(payload)
    end
  end

  %w[namespace buyer servicePlanPriceId].each do |field|
    it "requires checkout #{field} for correlation with the authenticated request" do
      payload = fixtures.fetch('checkoutResponse')
      payload.delete(field)
      expect { described_class.validate!('checkoutResponse', payload) }.to raise_error(Autonomia::Financial::StoreContractError)
    end
  end

  it 'rejects floating point event versions and leading zeroes' do
    payload = fixtures.fetch('storeEvent')
    payload['accessVersion'] = 9_007_199_254_740_993
    expect { described_class.validate!('storeEvent', payload) }.to raise_error(Autonomia::Financial::StoreContractError)
    payload['accessVersion'] = '01'
    expect { described_class.validate!('storeEvent', payload) }.to raise_error(Autonomia::Financial::StoreContractError)
  end

  it 'does not expose invalid payload values in errors' do
    expect { described_class.validate!('namespace', 'sensitive-value') }
      .to raise_error(Autonomia::Financial::StoreContractError, 'Invalid Financial store contract payload.')
  end

  it 'keeps equal metric keys belonging to different catalog services separate' do
    catalog = fixtures.fetch('catalog')
    expect(catalog.fetch('data').map { |item| item.dig('service', 'id') }.uniq.length).to eq(2)
    expect(catalog.fetch('data').map { |item| item.dig('offers', 0, 'limits', 0, 'metricKey') }.uniq).to eq(['accounts_allowed'])
    expect(described_class.validate!('catalogResponse', catalog)).to eq(catalog)
  end

  it 'accepts tokens and transaction resources without an account-specific engine' do
    request = fixtures.fetch('reserveRequest')
    request.merge!('metricKey' => 'tokens_used', 'quantity' => 512, 'resourceRef' => { 'type' => 'ai_operation', 'id' => 'operation:1' })
    expect(described_class.validate!('reserveRequest', request)).to eq(request)
  end

  it 'rejects executable targets and an insecure icon' do
    payload = fixtures.fetch('catalog')
    payload['data'][0]['service']['logoUrl'] = 'javascript:alert(1)'
    payload['data'][0]['target'] = { 'type' => 'agent', 'callbackUrl' => 'https://untrusted.example.test' }
    expect { described_class.validate!('catalogResponse', payload) }.to raise_error(Autonomia::Financial::StoreContractError)
  end
end
