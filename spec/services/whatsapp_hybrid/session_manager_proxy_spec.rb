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
  let(:assigner) { instance_double(WhatsappProxy::Assigner, enabled?: true, mark_applied!: 1, release!: 1) }
  let(:manager) { described_class.new(connection, client: client, proxy_assigner: assigner) }
  let(:proxy) { webshare_proxy(id: 7, address: '10.0.0.7') }
  let(:proxy_config) { { server: '10.0.0.7:6000', username: 'user-7', password: 'senha-7' } }

  before { Redis::Alfred.delete("whatsapp_proxy:rewrite:#{session}") }

  def remote(proxy: nil, webhook: true, status: 'WORKING')
    config = { 'ignore' => {}, 'metadata' => { 'kept' => 'yes' } }
    config['webhooks'] = [{ 'url' => connection.webhook_url }] if webhook
    config['proxy'] = proxy if proxy
    { 'status' => status, 'config' => config }
  end

  def assign!(address = '10.0.0.7')
    WhatsappProxy::Assignment.create!(session_name: session, account_id: connection.account_id, pool: 'isp',
                                      webshare_proxy_id: '7', proxy_address: address, proxy_port: 6000, assigned_at: 1.day.ago)
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

  it 'frees the IP when the engine refuses to create the session' do
    allow(client).to receive(:get_session).and_return({})
    allow(assigner).to receive(:for).and_return(proxy)
    allow(client).to receive(:create_session).and_raise(Waha::Client::Error, 'boom')

    expect { manager.ensure_session! }.to raise_error(Waha::Client::Error)
    expect(assigner).to have_received(:release!).with(session)
  end

  it 'recreates a lost session with proxy on reconnect' do
    allow(client).to receive(:get_session).and_return({}, {}, {})
    allow(assigner).to receive(:for).and_return(proxy)

    manager.reconnect!

    expect(client).to have_received(:create_session).with(session, start: true, config: hash_including(proxy: proxy_config))
  end

  it 'does nothing on refresh when the session already has the assigned proxy (with or without http://)' do
    assign!
    allow(client).to receive(:get_session).and_return(remote(proxy: { 'server' => 'http://10.0.0.7:6000', 'password' => 'senha-7' }))
    allow(assigner).to receive(:for)

    expect { manager.refresh! }.not_to have_enqueued_job(WhatsappProxy::ApplyJob)
    expect(client).not_to have_received(:update_session)
    expect(assigner).not_to have_received(:for)
  end

  it 'never writes the proxy during the request: refresh only enqueues the change, once per hour' do
    allow(client).to receive(:get_session).and_return(remote)
    allow(assigner).to receive(:for)

    expect { 3.times { manager.refresh! } }.to have_enqueued_job(WhatsappProxy::ApplyJob).with(session).exactly(:once)
    expect(client).not_to have_received(:update_session)
    expect(assigner).not_to have_received(:for)
  end

  it 'does not enqueue while the session is not connected' do
    allow(client).to receive(:get_session).and_return(remote(status: 'SCAN_QR_CODE'))

    expect { manager.refresh! }.not_to have_enqueued_job(WhatsappProxy::ApplyJob)
  end

  it 'treats a Redis failure as cooling down (fails closed)' do
    allow(client).to receive(:get_session).and_return(remote)
    allow(Redis::Alfred).to receive(:set).and_raise(Redis::CannotConnectError)

    expect { manager.refresh! }.not_to have_enqueued_job(WhatsappProxy::ApplyJob)
  end

  it 'keeps the hand-made proxy and unknown keys when rewriting the webhook, without sending apps' do
    manual = { 'server' => '200.1.1.1:3128', 'username' => 'u', 'password' => 'p' }
    allow(client).to receive(:get_session).and_return(remote(proxy: manual, webhook: false))
    allow(assigner).to receive(:enabled?).and_return(false)

    manager.refresh!

    expect(client).to have_received(:update_session).with(
      session, config: hash_including('proxy' => manual, 'metadata' => { 'kept' => 'yes' },
                                      'webhooks' => [hash_including('url' => connection.webhook_url)])
    )
  end

  it 'never touches the proxy while sending a message' do
    allow(client).to receive(:get_session).and_return(remote)

    expect { manager.refresh!(sync_proxy: false) }.not_to have_enqueued_job(WhatsappProxy::ApplyJob)
    expect(client).not_to have_received(:update_session)
  end

  it 'swaps a dead IP for a new one on reconnect, merged over the remote config' do
    assign!
    allow(client).to receive(:get_session).and_return(remote(proxy: { 'server' => '10.0.0.7:6000' }))
    new_proxy = webshare_proxy(id: 8, address: '10.0.0.8')
    allow(assigner).to receive(:for).with(session).and_return(new_proxy)

    manager.reconnect!

    expect(client).to have_received(:update_session).with(
      session, config: hash_including('proxy' => hash_including('server' => '10.0.0.8:6000'), 'metadata' => { 'kept' => 'yes' })
    )
    expect(assigner).to have_received(:mark_applied!).with(session, new_proxy)
  end

  it 'behaves as before the proxy while WHATSAPP_PROXY_ENABLED is off, even with the Webshare key' do
    allow(client).to receive(:get_session).and_return(remote)
    real = WhatsappProxy::Assigner.new(engine: client, pools: { isp: fake_pool('isp', [proxy]) })

    with_modified_env(WHATSAPP_PROXY_ENABLED: nil) do
      expect { described_class.new(connection, client: client, proxy_assigner: real).refresh! }
        .not_to have_enqueued_job(WhatsappProxy::ApplyJob)
    end

    expect(client).not_to have_received(:update_session)
  end

  it 'logs a failed update without the credential' do
    assign!('10.0.0.9')
    allow(client).to receive(:get_session).and_return(remote(proxy: { 'server' => '10.0.0.9:6000' }, webhook: false))
    allow(assigner).to receive(:for).and_return(proxy)
    allow(client).to receive(:logout_session).and_raise(Waha::Client::Error, 'x')
    allow(client).to receive(:restart_session)
    allow(client).to receive(:update_session).and_raise(Waha::Client::Error, 'WAHA PUT -> 400: [FILTERED]')

    log = capture_log { manager.reconnect! }

    expect(log).to include('session config update failed')
    expect(log).not_to include('senha-7')
  end
end
