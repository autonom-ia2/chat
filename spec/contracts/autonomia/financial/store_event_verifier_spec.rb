require_relative 'store_spec_helper'
require_relative '../../../../app/services/autonomia/financial/store_configuration'
require_relative '../../../../app/services/autonomia/financial/store_checkout_contract'
require_relative '../../../../app/services/autonomia/financial/store_event_verifier'

RSpec.describe Autonomia::Financial::StoreEventVerifier do
  let(:fixture) { JSON.parse(File.read(File.expand_path('../../../fixtures/autonomia_store/contracts.v1.json', __dir__))) }
  let(:configuration) do
    Autonomia::Financial::StoreConfiguration.new(
      'FINANCIAL_STORE_API_KEY' => 'example-scoped-key',
      'FINANCIAL_STORE_ACTOR_ASSERTION_SECRET' => 'example-assertion-secret-not-real-32',
      'FINANCIAL_STORE_INSTALLATION_ID' => fixture['namespace']['installationId'],
      'FINANCIAL_STORE_PRODUCT_CATALOG_ITEM_ID' => fixture['namespace']['productCatalogItemId']
    )
  end
  let(:secret) { 'example-webhook-secret-independent-32' }
  let(:verifier) { described_class.new(configuration: configuration, secret: secret) }
  let(:body) { JSON.generate(fixture['storeEvent']) }
  let(:now) { Time.iso8601('2026-10-13T12:00:00Z').to_i }
  let(:headers) do
    id = fixture['storeEvent']['eventId']
    { 'X-Store-Timestamp' => now.to_s, 'X-Store-Event-Id' => id,
      'X-Store-Signature' => "v1=#{OpenSSL::HMAC.hexdigest('SHA256', secret, "#{now}.#{id}.#{body}")}" }
  end

  it 'verifies exact raw bytes, event ID, clock and installation before returning data' do
    expect(verifier.verify!(body: body, headers: headers, now: now)).to eq(fixture['storeEvent'])
  end

  it 'rejects tampered bytes and expired or future timestamps' do
    expect { verifier.verify!(body: "#{body} ", headers: headers, now: now) }
      .to raise_error(Autonomia::Financial::StoreClientError) { |e| expect(e.status).to eq(401) }
    [now - 301, now + 301].each do |outside|
      expect { verifier.verify!(body: body, headers: headers, now: outside) }
        .to raise_error(Autonomia::Financial::StoreClientError) { |e| expect(e.status).to eq(401) }
    end
  end

  it 'rejects foreign namespaces even with a valid signature' do
    fixture['storeEvent']['namespace']['installationId'] = 'other'
    expect { verifier.verify!(body: body, headers: headers, now: now) }
      .to raise_error(Autonomia::Financial::StoreClientError) { |e| expect(e.status).to eq(403) }
  end

  it 'rejects oversized payloads and secret reuse' do
    expect { verifier.verify!(body: 'x' * (described_class::MAX_BODY_BYTES + 1), headers: {}, now: now) }
      .to raise_error(Autonomia::Financial::StoreClientError) { |e| expect(e.status).to eq(413) }
    expect { described_class.new(configuration: configuration, secret: configuration.assertion_secret) }
      .to raise_error(Autonomia::Financial::StoreClientError) { |e| expect(e.status).to eq(503) }
  end
end
