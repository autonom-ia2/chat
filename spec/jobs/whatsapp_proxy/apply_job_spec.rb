require 'rails_helper'

RSpec.describe WhatsappProxy::ApplyJob do
  let(:webshare) { instance_double(Webshare::Client, configured?: true) }
  let(:client) { instance_double(Waha::Client, update_session: {}, list_sessions: []) }
  let(:proxy) { webshare_proxy(id: 2, address: '10.0.0.2') }

  around { |example| with_modified_env(WHATSAPP_PROXY_ENABLED: 'true') { example.run } }

  before do
    allow(Webshare::Client).to receive(:new).and_return(webshare)
    allow(Waha::Client).to receive(:new).and_return(client)
    allow(webshare).to receive(:proxies).and_return([proxy])
    WhatsappProxy::Assignment.create!(session_name: '5511900000001', webshare_proxy_id: '2', proxy_address: '10.0.0.2',
                                      proxy_port: 6000, assigned_at: 1.day.ago)
  end

  it 'swaps the proxy of a WAHA session keeping its config and apps, then records the credential' do
    apps = [{ 'id' => 'app_1', 'app' => 'chatwoot' }, { 'id' => 'br_1', 'app' => 'brazilian-phone-numbers' }]
    allow(client).to receive(:get_session).and_return({ 'config' => { 'ignore' => { 'groups' => true }, 'proxy' => { 'server' => 'x' } } })
    allow(client).to receive(:list_apps).with('5511900000001').and_return(apps)

    described_class.perform_now('5511900000001')

    expected = { 'ignore' => { 'groups' => true },
                 'proxy' => { 'server' => '10.0.0.2:6000', 'username' => 'user-2', 'password' => 'senha-2' } }
    expect(client).to have_received(:update_session).with('5511900000001', config: expected, apps: apps)
    expect(WhatsappProxy::Assignment.last.credential_digest).to eq(proxy.credential_digest)
  end

  it 'does not touch the engine while WHATSAPP_PROXY_ENABLED is off' do
    allow(client).to receive(:get_session)

    with_modified_env(WHATSAPP_PROXY_ENABLED: 'false') { described_class.perform_now('5511900000001') }

    expect(client).not_to have_received(:update_session)
  end

  it 'keeps the credential pending when the engine fails, so the next run retries' do
    allow(client).to receive(:get_session).and_raise(Waha::Client::Error, 'down')

    described_class.perform_now('5511900000001')

    expect(WhatsappProxy::Assignment.last.credential_digest).to be_nil
  end
end
