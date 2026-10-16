require 'rails_helper'

RSpec.describe 'Financial store callback', type: :request do
  let(:fixture) { JSON.parse(Rails.root.join('spec/fixtures/autonomia_store/checkout.v1.json').read) }
  let(:event) { fixture.fetch('entitlementsSnapshotEvent') }
  let(:secret) { 'fictitious-webhook-secret-isolated-32' }
  let(:body) { event.to_json }
  let(:timestamp) { Time.current.to_i.to_s }
  let(:headers) do
    {
      'CONTENT_TYPE' => 'application/json', 'X-Store-Event-Id' => event.fetch('eventId'), 'X-Store-Timestamp' => timestamp,
      'X-Store-Signature' => "v1=#{OpenSSL::HMAC.hexdigest('SHA256', secret, "#{timestamp}.#{event.fetch('eventId')}.#{body}")}"
    }
  end

  around do |example|
    with_modified_env('FINANCIAL_STORE_WEBHOOK_SECRET' => secret) { example.run }
  end

  before do
    configuration = instance_double(
      Autonomia::Financial::StoreConfiguration, namespace: event.fetch('namespace').deep_dup,
                                                api_key: 'fictitious-api-key', assertion_secret: 'fictitious-actor-secret-independent'
    )
    allow(Autonomia::Financial::StoreConfiguration).to receive(:new).and_return(configuration)
  end

  it 'persists the verified event before acknowledging and scheduling processing' do
    allow(Autonomia::Store::EventJob).to receive(:perform_later) do |id|
      expect(Autonomia::Store::Event.find(id).state).to eq('pending')
    end
    post '/api/autonomia/financial/store-events', params: body, headers: headers
    expect(response).to have_http_status(:accepted)
    expect(Autonomia::Store::Event.count).to eq(1)
    expect(Autonomia::Store::EventJob).to have_received(:perform_later).with(event.fetch('eventId'))
  end

  it 'deduplicates a processed event without scheduling its effects again' do
    Autonomia::Store::Event.create!(id: event.fetch('eventId'), body_sha256: Digest::SHA256.hexdigest(body),
                                    payload: event, state: 'processed', processed_at: Time.current)
    allow(Autonomia::Store::EventJob).to receive(:perform_later)
    post '/api/autonomia/financial/store-events', params: body, headers: headers
    expect(response).to have_http_status(:accepted)
    expect(Autonomia::Store::Event.count).to eq(1)
    expect(Autonomia::Store::EventJob).not_to have_received(:perform_later)
  end

  it 'rejects a changed payload under the same event ID' do
    Autonomia::Store::Event.create!(id: event.fetch('eventId'), body_sha256: 'different-digest', payload: event)
    post '/api/autonomia/financial/store-events', params: body, headers: headers
    expect(response).to have_http_status(:conflict)
  end

  it 'rejects a forged signature without persisting data' do
    post '/api/autonomia/financial/store-events', params: body, headers: headers.merge('X-Store-Signature' => "v1=#{'0' * 64}")
    expect(response).to have_http_status(:unauthorized)
    expect(Autonomia::Store::Event.count).to eq(0)
  end

  it 'rejects events outside the freshness window' do
    stale = (301.seconds.ago).to_i.to_s
    signature = "v1=#{OpenSSL::HMAC.hexdigest('SHA256', secret, "#{stale}.#{event.fetch('eventId')}.#{body}")}"
    post '/api/autonomia/financial/store-events', params: body,
                                                  headers: headers.merge('X-Store-Timestamp' => stale, 'X-Store-Signature' => signature)
    expect(response).to have_http_status(:unauthorized)
    expect(Autonomia::Store::Event.count).to eq(0)
  end

  it 'reschedules a persisted pending event after a delivery retry' do
    Autonomia::Store::Event.create!(id: event.fetch('eventId'), body_sha256: Digest::SHA256.hexdigest(body), payload: event)
    allow(Autonomia::Store::EventJob).to receive(:perform_later)
    post '/api/autonomia/financial/store-events', params: body, headers: headers
    expect(response).to have_http_status(:accepted)
    expect(Autonomia::Store::Event.count).to eq(1)
    expect(Autonomia::Store::EventJob).to have_received(:perform_later).with(event.fetch('eventId'))
  end

  it 'rejects a validly signed event from another installation' do
    event['namespace']['installationId'] = 'other-installation'
    post '/api/autonomia/financial/store-events', params: body, headers: headers
    expect(response).to have_http_status(:forbidden)
    expect(Autonomia::Store::Event.count).to eq(0)
  end
end
