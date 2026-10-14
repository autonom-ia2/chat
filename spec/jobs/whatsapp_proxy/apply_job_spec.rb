require 'rails_helper'

RSpec.describe WhatsappProxy::ApplyJob do
  let(:webshare) { instance_double(Webshare::Client, configured?: true) }
  let(:client) { instance_double(Waha::Client, update_session: {}, list_sessions: [], list_apps: []) }
  let(:proxy) { webshare_proxy(id: 2, address: '10.0.0.2') }
  let(:account) { create(:account) }
  let(:session) { '5511900000001' }

  around do |example|
    with_modified_env(WHATSAPP_PROXY_ENABLED: 'true', WEBSHARE_DATACENTER_PROXY_ADDRESSES: '10.0.0.2') { example.run }
  end

  before do
    allow(Webshare::Client).to receive(:new).and_return(webshare)
    allow(Waha::Client).to receive(:new).and_return(client)
    allow(webshare).to receive(:proxies).and_return([proxy])
    Redis::Alfred.delete("whatsapp_proxy:apply:#{session}")
    waha_session!(session, account)
    assign_proxy!(session, proxy, account: account)
  end

  def remote(server:, username: 'user-2', password: 'senha-2')
    { 'status' => 'WORKING', 'me' => { 'id' => '5511900000001@c.us' },
      'config' => { 'ignore' => {}, 'proxy' => { 'server' => server, 'username' => username, 'password' => password } } }
  end

  it 'swaps the proxy through the SessionUpdater and records the credential' do
    allow(client).to receive(:get_session).and_return(remote(server: '10.0.0.1:6000', username: 'x'), remote(server: '10.0.0.2:6000'))

    described_class.perform_now(session)

    expect(client).to have_received(:update_session)
      .with(session, config: hash_including('proxy' => hash_including('server' => '10.0.0.2:6000'))).once
    expect(WhatsappProxy::Assignment.last.credential_digest).to eq(proxy.credential_digest)
  end

  it 'does nothing when the engine already has this proxy with this credential' do
    allow(client).to receive(:get_session).and_return(remote(server: 'http://10.0.0.2:6000'))

    described_class.perform_now(session)

    expect(client).not_to have_received(:update_session)
    expect(WhatsappProxy::Assignment.last.credential_digest).to eq(proxy.credential_digest)
  end

  it 'reapplies when the credential of the same IP changed' do
    allow(client).to receive(:get_session).and_return(remote(server: '10.0.0.2:6000', password: 'antiga'), remote(server: '10.0.0.2:6000'))

    described_class.perform_now(session)

    expect(client).to have_received(:update_session).once
  end

  it 'repairs a session stuck in STARTING (its IP vanished), waiting for WORKING' do
    starting = remote(server: '10.0.0.9:6000', username: 'x').merge('status' => 'STARTING')
    allow(client).to receive(:get_session).and_return(starting, remote(server: '10.0.0.2:6000'))

    described_class.perform_now(session)

    expect(client).to have_received(:update_session).once
    expect(WhatsappProxy::Assignment.last.credential_digest).to eq(proxy.credential_digest)
  end

  it 'leaves a session asking for a QR code alone (unlinked device, not the proxy)' do
    allow(client).to receive(:get_session).and_return(remote(server: '10.0.0.9:6000').merge('status' => 'SCAN_QR_CODE'))

    described_class.perform_now(session)

    expect(client).not_to have_received(:update_session)
  end

  it 'never runs twice at the same time for the same session' do
    Redis::Alfred.set("whatsapp_proxy:apply:#{session}", '1', nx: true, ex: 60)
    allow(client).to receive(:get_session)

    described_class.perform_now(session)

    expect(client).not_to have_received(:get_session)
    expect(Redis::Alfred.get("whatsapp_proxy:apply:#{session}")).to be_present
  end

  it 'frees the assignment when the engine no longer has the session' do
    allow(client).to receive(:get_session).and_raise(Waha::Client::NotFound, '404')

    described_class.perform_now(session)

    expect(WhatsappProxy::Assignment.count).to eq(0)
  end

  it 'does not touch the engine while WHATSAPP_PROXY_ENABLED is off' do
    allow(client).to receive(:get_session)

    with_modified_env(WHATSAPP_PROXY_ENABLED: 'false') { described_class.perform_now(session) }

    expect(client).not_to have_received(:get_session)
  end

  it 'keeps the credential pending when the engine fails, so the next run retries' do
    allow(client).to receive(:get_session).and_raise(Waha::Client::Error, 'down')

    described_class.perform_now(session)

    expect(WhatsappProxy::Assignment.last.credential_digest).to be_nil
  end
end
