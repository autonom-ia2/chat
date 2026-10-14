require 'rails_helper'

RSpec.describe Waha::Client do
  let(:config) { class_double(Waha::Config, api_url: 'https://waha.example', api_key: 'test-key') }
  let(:client) { described_class.new(config: config) }

  describe '#check_contact_exists' do
    let(:url) { 'https://waha.example/api/contacts/check-exists?phone=5511912345678&session=vendas' }

    it 'passes the per-call timeout to HTTParty and keeps the default when none is given' do
      stub_request(:get, url).to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                                        body: { numberExists: true, chatId: '5511912345678@c.us' }.to_json)
      allow(HTTParty).to receive(:get).and_call_original

      result = client.check_contact_exists(phone: '5511912345678', session: 'vendas', timeout: 5)
      client.check_contact_exists(phone: '5511912345678', session: 'vendas')

      expect(result).to eq('numberExists' => true, 'chatId' => '5511912345678@c.us')
      expect(HTTParty).to have_received(:get).with(url, hash_including(timeout: 5)).once
      expect(HTTParty).to have_received(:get).with(url, hash_including(timeout: described_class::DEFAULT_TIMEOUT)).once
    end

    it 'fills Error#status with the HTTP code the engine answered' do
      stub_request(:get, url).to_return(status: 429, body: 'slow down')
      expect { client.check_contact_exists(phone: '5511912345678', session: 'vendas') }
        .to raise_error(described_class::Error) { |error| expect(error.status).to eq(429) }

      stub_request(:get, url).to_return(status: 404, body: 'no session')
      expect { client.check_contact_exists(phone: '5511912345678', session: 'vendas') }
        .to raise_error(described_class::NotFound) { |error| expect(error.status).to eq(404) }
    end

    it 'leaves Error#status empty when the engine did not answer' do
      stub_request(:get, url).to_raise(Net::ReadTimeout)
      expect { client.check_contact_exists(phone: '5511912345678', session: 'vendas', timeout: 5) }
        .to raise_error(described_class::Timeout) { |error| expect(error.status).to be_nil }

      stub_request(:get, url).to_raise(Errno::ECONNREFUSED)
      expect { client.check_contact_exists(phone: '5511912345678', session: 'vendas') }
        .to raise_error(described_class::Error) { |error| expect(error.status).to be_nil }
    end
  end

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

  it 'never puts the proxy credential in the error when the engine echoes it (#1516)' do
    config = { ignore: {}, proxy: { server: '10.0.0.9:6000', username: 'user-9', password: 'senha-9' } }
    stub_request(:post, 'https://waha.example/api/sessions')
      .to_return(status: 400, body: '{"message":"bad proxy user-9:senha-9@10.0.0.9:6000"}')

    expect { client.create_session('5511999999999', config: config) }.to raise_error(described_class::Error) { |error|
      expect(error.message).not_to include('senha-9')
      expect(error.message).not_to include('user-9')
      expect(error.message).to include('[FILTERED]')
    }
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
