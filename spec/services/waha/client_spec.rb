require 'rails_helper'

RSpec.describe Waha::Client do
  let(:config) { class_double(Waha::Config, api_url: 'https://waha.example', api_key: 'test-key') }
  let(:client) { described_class.new(config: config) }

  it 'creates a session with apps when provided' do
    apps = [{ id: 'br_123', session: '5511999999999', app: 'brazilian-phone-numbers', enabled: true, config: {} }]
    request = stub_request(:post, 'https://waha.example/api/sessions')
              .with do |http_request|
      body = JSON.parse(http_request.body)
      body['name'] == '5511999999999' && body['start'] == true && body['apps'] == apps.map(&:deep_stringify_keys)
    end.to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: { name: '5511999999999' }.to_json)

    client.create_session('5511999999999', start: true, config: {}, apps: apps)

    expect(request).to have_been_requested.once
  end

  it 'updates a session while preserving the supplied config and full app list' do
    config = { 'ignore' => { 'groups' => true } }
    apps = [{ 'id' => 'app_1', 'session' => '5511999999999', 'app' => 'chatwoot', 'config' => {} }]
    request = stub_request(:put, 'https://waha.example/api/sessions/5511999999999')
              .with(body: { config: config, apps: apps }.to_json)
              .to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                         body: { name: '5511999999999', config: config, apps: apps }.to_json)

    result = client.update_session('5511999999999', config: config, apps: apps)

    expect(result).to include('name' => '5511999999999')
    expect(request).to have_been_requested.once
  end

  it 'detects the Brazilian resolver module when the route exists but the session app is not configured' do
    request = stub_request(:get, 'https://waha.example/api/apps/brazilian-phone-numbers/5511999999999/cache/stats')
              .to_return(
                status: 404,
                headers: { 'Content-Type' => 'application/json' },
                body: {
                  message: "App 'brazilian-phone-numbers' is not enabled for session '5511999999999'",
                  error: 'Not Found',
                  statusCode: 404
                }.to_json
              )

    expect(client.brazilian_phone_numbers_available?('5511999999999')).to be(true)
    expect(request).to have_been_requested.once
  end

  it 'reports the Brazilian resolver module unavailable when its route is not registered' do
    request = stub_request(:get, 'https://waha.example/api/apps/brazilian-phone-numbers/5511999999999/cache/stats')
              .to_return(
                status: 404,
                headers: { 'Content-Type' => 'application/json' },
                body: {
                  message: 'Cannot GET /api/apps/brazilian-phone-numbers/5511999999999/cache/stats',
                  error: 'Not Found',
                  statusCode: 404
                }.to_json
              )

    expect(client.brazilian_phone_numbers_available?('5511999999999')).to be(false)
    expect(request).to have_been_requested.once
  end

  it 'raises on an unexpected resolver capability response' do
    stub_request(:get, 'https://waha.example/api/apps/brazilian-phone-numbers/5511999999999/cache/stats')
      .to_return(status: 500, body: '{}')

    expect { client.brazilian_phone_numbers_available?('5511999999999') }
      .to raise_error(Waha::Client::Error, /WAHA GET/)
  end

  it 'reads an existing app by id' do
    request = stub_request(:get, 'https://waha.example/api/apps/app_123')
              .with(headers: { 'X-Api-Key' => 'test-key' })
              .to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                         body: { id: 'app_123', app: 'chatwoot' }.to_json)

    expect(client.get_app('app_123')).to include('id' => 'app_123', 'app' => 'chatwoot')
    expect(request).to have_been_requested.once
  end

  it 'updates an existing app with the complete payload' do
    payload = {
      'id' => 'app_123',
      'session' => '5511999999999',
      'app' => 'chatwoot',
      'enabled' => true,
      'config' => { 'conversations' => { 'outgoing' => 'message' } }
    }
    request = stub_request(:put, 'https://waha.example/api/apps/app_123')
              .with(headers: { 'X-Api-Key' => 'test-key' }, body: payload.to_json)
              .to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: payload.to_json)

    expect(client.update_app('app_123', payload)).to eq(payload)
    expect(request).to have_been_requested.once
  end
end
