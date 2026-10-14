require 'rails_helper'

# #1516: a sessão do Híbrido nasce com IP próprio, e regravar webhook, atualizar ou reconectar nunca apaga o proxy.
describe WhatsappHybrid::SessionManager do
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:session) { 'hybrid-proxy-test' }
  let(:connection) do
    WhatsappHybrid::Connection.create!(account: channel.account, inbox: channel.inbox, session_name: session, status: 'connected')
  end
  let(:client) do
    instance_double(Waha::Client, create_session: {}, update_session: {}, start_session: {}, logout_session: {},
                                  capping: { 'cappingStatus' => 'NONE' })
  end
  let(:assigner) { instance_double(WhatsappProxy::Assigner, enabled?: true, mark_applied!: 1) }
  let(:manager) { described_class.new(connection, client: client, proxy_assigner: assigner) }
  let(:proxy) { webshare_proxy(id: 7, address: '10.0.0.7') }
  let(:proxy_config) { { server: '10.0.0.7:6000', username: 'user-7', password: 'senha-7' } }

  before { Redis::Alfred.delete("whatsapp_proxy:rewrite:#{session}") }

  def remote(proxy: nil, webhook: true)
    config = { 'ignore' => {} }
    config['webhooks'] = [{ 'url' => connection.webhook_url }] if webhook
    config['proxy'] = proxy if proxy
    { 'status' => 'WORKING', 'config' => config }
  end

  def assign!(address = '10.0.0.7')
    WhatsappProxy::Assignment.create!(session_name: session, webshare_proxy_id: '7', proxy_address: address,
                                      proxy_port: 6000, assigned_at: 1.day.ago)
  end

  it 'creates the session with its own proxy and records it as applied' do
    allow(client).to receive(:get_session).and_return({}, {})
    allow(assigner).to receive(:for).with(session).and_return(proxy)

    manager.ensure_session!

    expect(client).to have_received(:create_session).with(session, start: true, config: hash_including(proxy: proxy_config))
    expect(assigner).to have_received(:mark_applied!).with(session, proxy)
  end

  it 'creates the session without proxy when none is available' do
    allow(client).to receive(:get_session).and_return({}, {})
    allow(assigner).to receive(:for).and_return(nil)

    manager.ensure_session!

    expect(client).to have_received(:create_session).with(session, start: true, config: hash_excluding(:proxy))
  end

  it 'recreates a lost session with proxy on reconnect' do
    allow(client).to receive(:get_session).and_return({}, {}, {})
    allow(assigner).to receive(:for).and_return(proxy)

    manager.reconnect!

    expect(client).to have_received(:create_session).with(session, start: true, config: hash_including(proxy: proxy_config))
  end

  it 'does nothing on refresh when the session already has the assigned proxy' do
    assign!
    allow(client).to receive(:get_session).and_return(remote(proxy: { 'server' => '10.0.0.7:6000', 'password' => 'senha-7' }))
    allow(assigner).to receive(:for)

    manager.refresh!

    expect(client).not_to have_received(:update_session)
    expect(assigner).not_to have_received(:for)
  end

  it 'adds the proxy once when the session lacks it, without rewriting on every refresh' do
    allow(client).to receive(:get_session).and_return(remote)
    allow(assigner).to receive(:for).with(session, honor_backoff: true).and_return(proxy)

    3.times { manager.refresh! }

    expect(client).to have_received(:update_session)
      .with(session, config: hash_including(proxy: proxy_config, webhooks: [hash_including(url: connection.webhook_url)]), apps: nil).once
    expect(assigner).to have_received(:mark_applied!).with(session, proxy).once
  end

  it 'keeps the hand-made proxy when rewriting the webhook' do
    manual = { 'server' => '200.1.1.1:3128', 'username' => 'u', 'password' => 'p' }
    allow(client).to receive(:get_session).and_return(remote(proxy: manual, webhook: false))
    allow(assigner).to receive(:enabled?).and_return(false)

    manager.refresh!

    expect(client).to have_received(:update_session).with(session, config: hash_including(proxy: manual), apps: nil)
  end

  it 'never touches the proxy while sending a message' do
    allow(client).to receive(:get_session).and_return(remote)
    allow(assigner).to receive(:for)

    manager.refresh!(sync_proxy: false)

    expect(client).not_to have_received(:update_session)
    expect(assigner).not_to have_received(:for)
  end

  it 'swaps a dead IP for a new one on reconnect' do
    assign!
    allow(client).to receive(:get_session).and_return(remote(proxy: { 'server' => '10.0.0.7:6000' }))
    new_proxy = webshare_proxy(id: 8, address: '10.0.0.8')
    allow(assigner).to receive(:for).with(session, honor_backoff: false).and_return(new_proxy)

    manager.reconnect!

    expect(client).to have_received(:update_session)
      .with(session, config: hash_including(proxy: hash_including(server: '10.0.0.8:6000')), apps: nil)
  end

  it 'logs a failed update without the credential' do
    allow(client).to receive(:get_session).and_return(remote(webhook: false))
    allow(assigner).to receive(:for).and_return(proxy)
    allow(client).to receive(:update_session).and_raise(Waha::Client::Error, 'WAHA PUT -> 400: [FILTERED]')

    log = capture_log { manager.refresh! }

    expect(log).to include('session config update failed')
    expect(log).not_to include('senha-7')
  end
end
