require 'rails_helper'

# #1487: pausar/retomar o WhatsApp API pela aba, e os avisos que a aba recebe.
RSpec.describe 'WhatsApp Híbrido pause API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', phone_number: '+5511999993846',
                              sync_templates: false, validate_provider_config: false)
  end
  let(:client) { instance_double(Waha::Client) }
  let(:base) { "/api/v1/accounts/#{account.id}/whatsapp_hybrid_connections/#{channel.inbox.id}" }
  let(:working) { { 'status' => 'WORKING', 'me' => { 'id' => '5511999993846@c.us' } } }
  let(:stopped) { { 'status' => 'STOPPED', 'me' => { 'id' => '5511999993846@c.us' } } }
  let!(:connection) do
    WhatsappHybrid::Connection.create!(account: account, inbox: channel.inbox, session_name: 'hybrid-5511999993846',
                                       status: 'connected', connected_phone: '5511999993846', risk_accepted_at: Time.current)
  end

  around do |example|
    with_modified_env(WHATSAPP_HYBRID_ACCOUNT_IDS: account.id.to_s, WAHA_API_URL: 'http://waha.test', WAHA_API_KEY: 'k') { example.run }
  end

  before do
    allow(Waha::Client).to receive(:new).and_return(client)
    allow(client).to receive_messages(update_session: {}, stop_session: {}, start_session: {}, logout_session: {},
                                      capping: { 'cappingStatus' => 'NONE' }, timelock: { 'isActive' => false },
                                      list_sessions: [])
  end

  it 'refuses agents' do
    post "#{base}/pause", headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
    expect(client).not_to have_received(:stop_session)
  end

  it 'pauses without unlinking the device' do
    allow(client).to receive(:get_session).and_return(working, stopped)

    post "#{base}/pause", headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('paused' => true, 'routing_active' => false, 'phone' => '5511999993846')
    expect(client).not_to have_received(:logout_session)
  end

  it 'resumes the same session' do
    connection.update!(paused_at: Time.current, status: 'disconnected')
    allow(client).to receive(:get_session).and_return(stopped, working)

    post "#{base}/resume", headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body).to include('paused' => false, 'connected' => true)
    expect(client).to have_received(:start_session).with('hybrid-5511999993846')
  end

  it 'never reports connected while paused, even if the engine still says WORKING' do
    connection.update!(paused_at: Time.current)
    allow(client).to receive(:get_session).and_return(working)

    get base, headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body).to include('paused' => true, 'connected' => false, 'routing_active' => false)
    expect(client).not_to have_received(:start_session)
  end

  it 'answers a neutral error when the engine refuses the pause' do
    allow(client).to receive(:get_session).and_return(working)
    allow(client).to receive(:stop_session).and_raise(Waha::Client::Error.new('boom', status: 500))

    post "#{base}/pause", headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to eq('error' => 'pause_failed')
    expect(connection.reload).not_to be_paused
  end

  it 'refuses the pause, without saving it, when the engine cannot be read' do
    allow(client).to receive(:get_session).and_raise(Waha::Client::Timeout, 'timeout')

    post "#{base}/pause", headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body).to eq('error' => 'pause_failed')
    expect(client).not_to have_received(:stop_session)
    expect(connection.reload).not_to be_paused
  end

  it 'answers try again while another change holds the session' do
    allow(client).to receive(:get_session).and_return(working)
    Redis::Alfred.set(WhatsappProxy::SessionLock.key('hybrid-5511999993846'), 'other', ex: 60)

    post "#{base}/pause", headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body).to eq('error' => 'pause_failed')
    expect(client).not_to have_received(:stop_session)
  ensure
    Redis::Alfred.delete(WhatsappProxy::SessionLock.key('hybrid-5511999993846'))
  end

  it 'lists other WhatsApp API inboxes on the same number' do
    api = Channel::Api.create!(account: account, additional_attributes: { 'provider' => 'waha', 'session' => '551199993846' })
    create(:inbox, account: account, channel: api, name: 'Vendas WhatsApp')
    allow(client).to receive(:get_session).and_return(working)
    allow(client).to receive(:list_sessions).and_return([{ 'name' => '551199993846', 'status' => 'WORKING' }])

    get base, headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body).to include('same_number_inboxes' => ['Vendas WhatsApp'], 'paused' => false)
  end

  it 'warns before connecting, when there is no connection yet' do
    connection.delete
    api = Channel::Api.create!(account: account, additional_attributes: { 'provider' => 'waha', 'session' => '5511999993846' })
    create(:inbox, account: account, channel: api, name: 'Atendimento WhatsApp')
    allow(client).to receive(:list_sessions).and_return([{ 'name' => '5511999993846', 'status' => 'WORKING' }])

    get base, headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body).to include('status' => 'not_connected', 'same_number_inboxes' => ['Atendimento WhatsApp'])
  end

  it 'asks to try again in a few seconds when a paused session is still starting, without logging out' do
    connection.update!(paused_at: Time.current, status: 'disconnected')
    allow(Kernel).to receive(:sleep)
    allow(client).to receive(:get_session).and_return(stopped, { 'status' => 'STARTING' })

    post "#{base}/reconnect", headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to eq('error' => 'waking')
    expect(client).not_to have_received(:logout_session)
    expect(connection.reload).to be_paused
  end
end
