require 'rails_helper'

describe Whatsapp::SmbAppDataSync do
  let(:client) { Whatsapp::FacebookApiClient.new('test_token') }
  let(:api_version) { GlobalConfigService.load('WHATSAPP_API_VERSION', 'v22.0') }
  let(:url) { "https://graph.facebook.com/#{api_version}/123456789/smb_app_data" }

  it 'is available on the Facebook API client' do
    expect(client).to respond_to(:start_smb_app_data_sync)
  end

  it 'posts the sync request to the SMB App Data endpoint and returns the parsed body' do
    stub_request(:post, url)
      .with(
        headers: { 'Authorization' => 'Bearer test_token', 'Content-Type' => 'application/json' },
        body: { messaging_product: 'whatsapp', sync_type: 'history' }.to_json
      )
      .to_return(status: 200, body: { messaging_product: 'whatsapp', request_id: 'req-1' }.to_json,
                 headers: { 'Content-Type' => 'application/json' })

    expect(client.start_smb_app_data_sync('123456789', 'history')).to include('request_id' => 'req-1')
  end

  it 'raises when Meta rejects the sync' do
    stub_request(:post, url).to_return(status: 400, body: { error: { message: 'bad' } }.to_json,
                                       headers: { 'Content-Type' => 'application/json' })

    expect { client.start_smb_app_data_sync('123456789', 'smb_app_state_sync') }.to raise_error(StandardError)
  end
end
