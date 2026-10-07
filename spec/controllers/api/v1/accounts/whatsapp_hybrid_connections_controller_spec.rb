require 'rails_helper'

RSpec.describe 'WhatsApp Híbrido connections API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', phone_number: '+5511999993846',
                              sync_templates: false, validate_provider_config: false)
  end
  let(:inbox) { channel.inbox }
  let(:client) { instance_double(Waha::Client) }
  let(:base) { "/api/v1/accounts/#{account.id}/whatsapp_hybrid_connections/#{inbox.id}" }
  let(:working) { { 'status' => 'WORKING', 'me' => { 'id' => '5511999993846@c.us' } } }

  around do |example|
    with_modified_env(WHATSAPP_HYBRID_ACCOUNT_IDS: account.id.to_s, WAHA_API_URL: 'http://waha.test', WAHA_API_KEY: 'k') { example.run }
  end

  before do
    allow(Waha::Client).to receive(:new).and_return(client)
    allow(client).to receive(:update_session)
    allow(client).to receive(:capping).and_return({ 'cappingStatus' => 'NONE', 'totalQuota' => -1, 'usedQuota' => 0 })
  end

  it 'hides the tab for accounts outside the allowlist' do
    with_modified_env(WHATSAPP_HYBRID_ACCOUNT_IDS: '') do
      get base, headers: admin.create_new_auth_token, as: :json
    end

    expect(response).to have_http_status(:not_found)
  end

  it 'refuses agents' do
    get base, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
  end

  it 'reports not connected before the first connection' do
    get base, headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body).to include('available' => true, 'connected' => false, 'status' => 'not_connected')
  end

  it 'creates a session without Chatwoot app or webhook and validates the number' do
    allow(client).to receive(:get_session).and_return({}, working)
    allow(client).to receive(:create_session)

    post "#{base}/connect", headers: admin.create_new_auth_token, as: :json

    webhook = hash_including(events: %w[session.status message.ack], hmac: hash_including(:key))
    expected_config = hash_including(ignore: hash_including(groups: true), webhooks: [webhook])
    expect(client).to have_received(:create_session).with('hybrid-5511999993846', start: true, config: expected_config)
    expect(response.parsed_body).to include('connected' => true, 'same_number' => true, 'risk_accepted' => false, 'routing_active' => false)
  end

  it 'records who accepted the risk and activates routing' do
    WhatsappHybrid::Connection.create!(account: account, inbox: inbox, session_name: 'hybrid-5511999993846',
                                       status: 'connected', connected_phone: '5511999993846')

    patch base, params: { risk_accepted: true }, headers: admin.create_new_auth_token, as: :json

    connection = WhatsappHybrid::Connection.last
    expect(connection.risk_accepted_by_id).to eq(admin.id)
    expect(response.parsed_body).to include('risk_accepted' => true, 'routing_active' => true)
  end

  it 'returns a pairing code for the cloud number' do
    WhatsappHybrid::Connection.create!(account: account, inbox: inbox, session_name: 'hybrid-5511999993846')
    allow(client).to receive(:request_pairing_code).with('hybrid-5511999993846', phone: '5511999993846').and_return({ 'code' => 'AB12-CD34' })

    post "#{base}/request_code", headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body).to eq('code' => 'AB12-CD34')
  end

  it 'recreates the session on reconnect when the engine lost it' do
    WhatsappHybrid::Connection.create!(account: account, inbox: inbox, session_name: 'hybrid-5511999993846', status: 'disconnected')
    allow(client).to receive(:get_session).and_return({}, {}, { 'status' => 'SCAN_QR_CODE' })
    allow(client).to receive(:create_session)

    post "#{base}/reconnect", headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(client).to have_received(:create_session)
    expect(WhatsappHybrid::Connection.last.status).to eq('awaiting_scan')
  end

  it 'disconnects, removes the connection and tears the session down in background' do
    WhatsappHybrid::Connection.create!(account: account, inbox: inbox, session_name: 'hybrid-5511999993846')

    expect { delete base, headers: admin.create_new_auth_token, as: :json }
      .to have_enqueued_job(WhatsappHybrid::TeardownSessionJob).with('hybrid-5511999993846')

    expect(response).to have_http_status(:no_content)
    expect(WhatsappHybrid::Connection.count).to eq(0)
  end

  it 'tears the session down when the official inbox is deleted' do
    WhatsappHybrid::Connection.create!(account: account, inbox: inbox, session_name: 'hybrid-5511999993846')
    allow(channel).to receive(:teardown_webhooks)

    expect { inbox.destroy! }.to have_enqueued_job(WhatsappHybrid::TeardownSessionJob).with('hybrid-5511999993846')
    expect(WhatsappHybrid::Connection.count).to eq(0)
  end
end
