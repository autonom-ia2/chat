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

  it 'lists chats with stable id ordering and pagination' do
    request = stub_request(:get, 'https://waha.example/api/5511999999999/chats')
              .with(query: { limit: '100', offset: '200', sortBy: 'id', sortOrder: 'asc' })
              .to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: '[]')

    expect(client.list_chats('5511999999999', limit: 100, offset: 200)).to eq([])
    expect(request).to have_been_requested.once
  end

  it 'recognizes the versioned original-source-ID capability on the authenticated version endpoint' do
    stub_request(:get, 'https://waha.example/api/server/version')
      .with(headers: { 'X-Api-Key' => 'test-key' })
      .to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                 body: { version: '2026.9.2', chat2youHistorySourceIds: 'v1' }.to_json)

    expect(client.history_source_ids_available?).to be(true)
  end

  it 'rejects an unpatched connector without guessing capability from its version' do
    stub_request(:get, 'https://waha.example/api/server/version')
      .to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: '{"version":"2026.9.2"}')

    expect(client.history_source_ids_available?).to be(false)
  end

  it 'maps a LID to the canonical phone identity' do
    request = stub_request(:get, 'https://waha.example/api/test-session/lids/12345%40lid')
              .to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: '{"pn":"16505551234@c.us"}')

    expect(client.get_lid_mapping('test-session', chat_id: '12345@lid')).to include('pn' => '16505551234@c.us')
    expect(request).to have_been_requested.once
  end

  it 'rejects an external media origin before sending the API key' do
    expect { client.download_media('https://external.example/api/files/image.png') }
      .to raise_error(Waha::Client::Error, 'history_media_origin_mismatch')
  end

  it 'downloads only its own file endpoint without following redirects' do
    file = Tempfile.new('history')
    allow(GlobalConfigService).to receive(:load).with('MAXIMUM_FILE_UPLOAD_SIZE', 40).and_return(40)
    expect(Down).to receive(:download).with(
      'https://waha.example/api/files/image.png',
      headers: { 'X-Api-Key' => 'test-key' }, max_redirects: 0, max_size: 40.megabytes, open_timeout: 10, read_timeout: 10
    ).and_return(file)
    expect(client.download_media('https://waha.example/api/files/image.png')).to eq(file)
    file.close!
  end

  it 'lists messages oldest first with an upper timestamp bound and media disabled' do
    request = stub_request(:get, 'https://waha.example/api/5511999999999/chats/5511999999999%40c.us/messages')
              .with(query: {
                      :limit => '100', :offset => '300', 'filter.timestamp.lte' => '1727745026',
                      :sortBy => 'timestamp', :sortOrder => 'asc', :downloadMedia => 'false'
                    })
              .to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: '[]')

    expect(client.list_messages('5511999999999', chat_id: '5511999999999@c.us', limit: 100, offset: 300,
                                                 before: 1_727_745_026)).to eq([])
    expect(request).to have_been_requested.once
  end

  it 'turns transient media download failures into a sanitized retryable read error' do
    allow(Down).to receive(:download).and_raise(Down::TimeoutError, 'private remote URL')

    expect { client.download_media('https://waha.example/api/files/image.png') }
      .to raise_error(Waha::Client::Error, 'history_media_read_failed Down::TimeoutError')
  end

  it 'gets a contact with encoded query values' do
    request = stub_request(:get, 'https://waha.example/api/contacts')
              .with(query: { session: '5511999999999', contactId: '5511999999999@c.us' })
              .to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: '{}')

    expect(client.get_contact('5511999999999', contact_id: '5511999999999@c.us')).to eq({})
    expect(request).to have_been_requested.once
  end

  it 'gets one message with media download enabled and encoded path values' do
    request = stub_request(
      :get,
      'https://waha.example/api/5511999999999/chats/5511999999999%40c.us/messages/false_5511999999999%40c.us_ABC'
    ).with(query: { downloadMedia: 'true' })
              .to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: '{}')

    expect(
      client.get_message(
        '5511999999999',
        chat_id: '5511999999999@c.us',
        message_id: 'false_5511999999999@c.us_ABC'
      )
    ).to eq({})
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
