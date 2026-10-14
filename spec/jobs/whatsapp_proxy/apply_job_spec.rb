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
    Redis::Alfred.delete(described_class.lock_key(session))
    Redis::Alfred.delete("whatsapp_proxy:alert:troca_desfeita:#{session}")
    waha_session!(session, account)
    assign_proxy!(session, proxy, account: account)
  end

  def remote(server:, username: 'user-2', password: 'senha-2', status: 'WORKING')
    { 'status' => status, 'me' => { 'id' => '5511900000001@c.us' },
      'config' => { 'ignore' => {}, 'proxy' => { 'server' => server, 'username' => username, 'password' => password } } }
  end

  # A atribuição já foi movida de 10.0.0.9 para 10.0.0.2 pela reconciliação (o anterior fica guardado).
  def moved_from_old!
    WhatsappProxy::Assignment.last.update!(previous_proxy_address: '10.0.0.9', previous_proxy_port: 6000,
                                           previous_webshare_proxy_id: '9', previous_credential_digest: 'antigo')
  end

  it 'swaps the proxy through the SessionUpdater, records the credential and forgets the previous IP' do
    moved_from_old!
    allow(client).to receive(:get_session).and_return(remote(server: '10.0.0.9:6000', username: 'x'), remote(server: '10.0.0.2:6000'))

    described_class.perform_now(session)

    expect(client).to have_received(:update_session)
      .with(session, config: hash_including('proxy' => hash_including('server' => '10.0.0.2:6000'))).once
    expect(WhatsappProxy::Assignment.last).to have_attributes(credential_digest: proxy.credential_digest, previous_proxy_address: nil,
                                                              apply_failures: 0)
  end

  it 'does nothing when the engine already has this proxy with this credential' do
    allow(client).to receive(:get_session).and_return(remote(server: 'http://10.0.0.2:6000'))

    described_class.perform_now(session)

    expect(client).not_to have_received(:update_session)
    expect(WhatsappProxy::Assignment.last.credential_digest).to eq(proxy.credential_digest)
  end

  it 'repairs a session stuck in STARTING (its IP vanished), waiting for WORKING' do
    allow(client).to receive(:get_session).and_return(remote(server: '10.0.0.9:6000', username: 'x', status: 'STARTING'),
                                                      remote(server: '10.0.0.2:6000'))

    described_class.perform_now(session)

    expect(client).to have_received(:update_session).once
  end

  it 'leaves a session asking for a QR code alone' do
    allow(client).to receive(:get_session).and_return(remote(server: '10.0.0.9:6000', status: 'SCAN_QR_CODE'))

    described_class.perform_now(session)

    expect(client).not_to have_received(:update_session)
  end

  describe 'undone change (H2)' do
    before do
      moved_from_old!
      allow(client).to receive(:get_session).and_return(remote(server: '10.0.0.9:6000', username: 'x'),
                                                        remote(server: '10.0.0.9:6000', status: 'STARTING'))
      stub_const('WhatsappProxy::SessionUpdater::HEALTH_ATTEMPTS', 1)
    end

    it 'puts the assignment back on the previous IP, counts a failure and alerts once' do
      log = capture_log { described_class.perform_now(session) }

      expect(WhatsappProxy::Assignment.last).to have_attributes(proxy_address: '10.0.0.9', credential_digest: 'antigo',
                                                                apply_failures: 1)
      expect(WhatsappProxy::Assignment.last).to be_in_backoff
      expect(log.scan('[alerta] troca_desfeita').size).to eq(1)
    end

    it 'alerts again only when the backoff reaches its maximum' do
      WhatsappProxy::Assignment.last.update!(apply_failures: 2)
      log = capture_log { described_class.perform_now(session) }
      expect(log).not_to include('[alerta] troca_desfeita')

      moved_from_old!
      WhatsappProxy::Assignment.last.update!(proxy_address: '10.0.0.2', apply_failures: WhatsappProxy::Assignment::BACKOFF.size - 1)
      Redis::Alfred.delete("whatsapp_proxy:alert:troca_desfeita:#{session}")
      log = capture_log { described_class.perform_now(session) }
      expect(log).to include('[alerta] troca_desfeita')
    end

    it 'leaves a brand new number pending (no previous IP) after an undone change' do
      WhatsappProxy::Assignment.last.update!(previous_proxy_address: nil, previous_proxy_port: nil, previous_webshare_proxy_id: nil,
                                             previous_credential_digest: nil)

      described_class.perform_now(session)

      expect(WhatsappProxy::Assignment.last).to have_attributes(pending?: true, apply_failures: 1)
    end
  end

  it 'never runs twice at the same time and only releases its own lock (M5)' do
    Redis::Alfred.set(described_class.lock_key(session), 'outro-job', nx: true, ex: 60)
    allow(client).to receive(:get_session)

    described_class.perform_now(session)

    expect(client).not_to have_received(:get_session)
    expect(Redis::Alfred.get(described_class.lock_key(session))).to eq('outro-job')
  end

  it 'releases its own lock at the end' do
    allow(client).to receive(:get_session).and_return(remote(server: '10.0.0.2:6000'))

    described_class.perform_now(session)

    expect(Redis::Alfred.get(described_class.lock_key(session))).to be_nil
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

  it 'counts a failure (backoff) when the engine fails' do
    allow(client).to receive(:get_session).and_raise(Waha::Client::Error, 'down')

    described_class.perform_now(session)

    expect(WhatsappProxy::Assignment.last).to have_attributes(credential_digest: nil, apply_failures: 1)
  end
end
