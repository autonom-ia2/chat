require 'rails_helper'

RSpec.describe Waha::Client do
  let(:config) { class_double(Waha::Config, api_url: 'https://waha.example', api_key: 'test-key') }
  let(:client) { described_class.new(config: config) }

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
