require 'rails_helper'

RSpec.describe WhatsappProxy::ApplyJob do
  let(:webshare) { instance_double(Webshare::Client, configured?: true) }
  let(:client) { instance_double(Waha::Client, update_session: {}, list_sessions: [], list_apps: []) }
  let(:proxy) { webshare_proxy(id: 2, address: '10.0.0.2') }
  let(:account) { create(:account) }
  let(:session) { '5511900000001' }

  around do |example|
    with_modified_env(WHATSAPP_PROXY_ENABLED: 'true', WEBSHARE_DATACENTER_PROXY_ADDRESSES: '10.0.0.2',
                      WEBSHARE_ISP_PROXY_ADDRESSES: '10.5.0.1') { example.run }
  end

  before do
    allow(Webshare::Client).to receive(:new).and_return(webshare)
    allow(Waha::Client).to receive(:new).and_return(client)
    allow(webshare).to receive(:proxies).and_return([proxy])
    Redis::Alfred.delete(WhatsappProxy::SessionLock.key(session))
    %w[troca_desfeita volta_falhou].each { |code| Redis::Alfred.delete("whatsapp_proxy:alert:#{code}:#{session}") }
    waha_session!(session, account)
    assign_proxy!(session, proxy, account: account)
  end

  def remote(server:, username: 'user-2', password: 'senha-2', status: 'WORKING')
    { 'status' => status, 'me' => { 'id' => '5511900000001@c.us' },
      'config' => { 'ignore' => {}, 'proxy' => { 'server' => server, 'username' => username, 'password' => password } } }
  end

  # A reconciliação já moveu a atribuição de 10.0.0.9 para 10.0.0.2 (o estado anterior fica guardado).
  def moved_from_old!
    WhatsappProxy::Assignment.last.update!(previous_proxy_address: '10.0.0.9', previous_proxy_port: 6000, previous_webshare_proxy_id: '9',
                                           previous_credential_digest: 'antigo', previous_pool: 'datacenter',
                                           previous_account_id: account.id, previous_origin: 'assigned')
  end

  def undone_by_engine!
    allow(client).to receive(:get_session).and_return(remote(server: '10.0.0.9:6000', username: 'x'),
                                                      remote(server: '10.0.0.9:6000', status: 'STARTING'))
    stub_const('WhatsappProxy::SessionUpdater::HEALTH_ATTEMPTS', 1)
  end

  it 'swaps the proxy through the SessionUpdater, records the credential and forgets the previous state' do
    moved_from_old!
    WhatsappProxy::Assignment.last.update!(apply_failures: 2, last_apply_failed_at: 1.day.ago)
    allow(client).to receive(:get_session).and_return(remote(server: '10.0.0.9:6000', username: 'x'), remote(server: '10.0.0.2:6000'))

    described_class.perform_now(session)

    expect(client).to have_received(:update_session)
      .with(session, config: hash_including('proxy' => hash_including('server' => '10.0.0.2:6000'))).once
    expect(WhatsappProxy::Assignment.last).to have_attributes(credential_digest: proxy.credential_digest, previous_proxy_address: nil,
                                                              previous_pool: nil, apply_failures: 0)
  end

  it 'confirms without PUT when the engine already has this proxy; the backoff, already over, is cleared' do
    WhatsappProxy::Assignment.last.update!(apply_failures: 2, last_apply_failed_at: 1.day.ago)
    allow(client).to receive(:get_session).and_return(remote(server: 'http://10.0.0.2:6000'))

    described_class.perform_now(session)

    expect(client).not_to have_received(:update_session)
    expect(WhatsappProxy::Assignment.last).to have_attributes(credential_digest: proxy.credential_digest, apply_failures: 0)
  end

  it 'never clears a backoff still running on a confirmation (model)' do
    assignment = WhatsappProxy::Assignment.last
    assignment.update!(apply_failures: 2, last_apply_failed_at: Time.current)

    assignment.confirmed!('x')

    expect(assignment.reload.apply_failures).to eq(2)
  end

  it 'leaves at once while the assignment is in backoff (M1)' do
    WhatsappProxy::Assignment.last.update!(apply_failures: 1, last_apply_failed_at: Time.current)
    allow(client).to receive(:get_session)

    described_class.perform_now(session)

    expect(client).not_to have_received(:get_session)
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
      undone_by_engine!
    end

    it 'puts the assignment back on the previous state, counts a failure and alerts once' do
      log = capture_log { described_class.perform_now(session) }

      expect(WhatsappProxy::Assignment.last).to have_attributes(proxy_address: '10.0.0.9', credential_digest: 'antigo',
                                                                apply_failures: 1, previous_pool: nil)
      expect(WhatsappProxy::Assignment.last).to be_in_backoff
      expect(log.scan('[alerta] troca_desfeita').size).to eq(1)
    end

    it 'does nothing when a duplicate job, already queued, runs after the reversion (M1)' do
      2.times { described_class.perform_now(session) }

      expect(client).to have_received(:update_session).twice # o PUT da troca e o PUT da volta, uma vez só
      expect(WhatsappProxy::Assignment.last.apply_failures).to eq(1)
    end

    it 'alerts again only when the backoff reaches its maximum' do
      WhatsappProxy::Assignment.last.update!(apply_failures: 2, last_apply_failed_at: 1.day.ago)
      log = capture_log { described_class.perform_now(session) }
      expect(log).not_to include('[alerta] troca_desfeita')

      moved_from_old!
      WhatsappProxy::Assignment.last.update!(proxy_address: '10.0.0.2', apply_failures: WhatsappProxy::Assignment::BACKOFF.size - 1,
                                             last_apply_failed_at: 2.days.ago)
      undone_by_engine!
      log = capture_log { described_class.perform_now(session) }
      expect(log).to include('[alerta] troca_desfeita')
    end

    it 'keeps the current IP (never pending by accident) when there was no saved state, only counting the failure' do
      WhatsappProxy::Assignment.last.update!(WhatsappProxy::Assignment::FORGET_PREVIOUS)

      described_class.perform_now(session)

      expect(WhatsappProxy::Assignment.last).to have_attributes(pending?: false, proxy_address: '10.0.0.2', apply_failures: 1)
    end
  end

  describe 'session already off WORKING (urgent drift, dead IP) — HIGH' do
    before { WhatsappProxy::Assignment.last.update!(apply_scheduled_at: Time.current) }

    it 'PUT accepted and proxy saved → applied, with no rollback and no wait for WORKING; the table keeps B' do
      allow(client).to receive(:get_session).and_return(remote(server: '10.0.0.9:6000', username: 'x', status: 'FAILED'),
                                                        remote(server: '10.0.0.2:6000', status: 'STARTING'))

      described_class.perform_now(session)

      expect(client).to have_received(:update_session).once
      expect(WhatsappProxy::Assignment.last).to have_attributes(proxy_address: '10.0.0.2', apply_failures: 0, apply_scheduled_at: nil,
                                                                credential_digest: proxy.credential_digest)
    end

    it 'proxy not saved → counts a failure, never rolls back, the table keeps B' do
      allow(client).to receive(:get_session).and_return(remote(server: '10.0.0.9:6000', username: 'x', status: 'FAILED'))

      described_class.perform_now(session)

      expect(client).to have_received(:update_session).once
      expect(WhatsappProxy::Assignment.last).to have_attributes(proxy_address: '10.0.0.2', apply_failures: 1, apply_scheduled_at: nil)
    end

    it 'PUT refused → counts a failure, never rolls back' do
      allow(client).to receive(:get_session).and_return(remote(server: '10.0.0.9:6000', username: 'x', status: 'FAILED'))
      allow(client).to receive(:update_session).and_raise(Waha::Client::Error, 'down')

      described_class.perform_now(session)

      expect(client).to have_received(:update_session).once
      expect(WhatsappProxy::Assignment.last).to have_attributes(proxy_address: '10.0.0.2', apply_failures: 1)
    end
  end

  it 'saves the IP the engine uses (known on the list) before the PUT of a drift that kept the table IP, and goes back to it' do
    old = webshare_proxy(id: 9, address: '10.0.0.9')
    allow(webshare).to receive(:proxies).and_return([proxy, old])
    undone_by_engine!

    described_class.perform_now(session)

    expect(WhatsappProxy::Assignment.last).to have_attributes(proxy_address: '10.0.0.9', webshare_proxy_id: '9', apply_failures: 1)
  end

  it 'clears the in-flight mark when the session is refused (QR)' do
    WhatsappProxy::Assignment.last.update!(apply_scheduled_at: Time.current)
    allow(client).to receive(:get_session).and_return(remote(server: '10.0.0.9:6000', status: 'SCAN_QR_CODE'))

    described_class.perform_now(session)

    expect(WhatsappProxy::Assignment.last.apply_scheduled_at).to be_nil
  end

  it 'reverts a plan change (WAHA number that became Hybrid) back to plan, account and origin (M3)' do
    hybrid_session!('hybrid-5511900000003', account)
    imported = webshare_proxy(id: 3, address: '10.0.0.3')
    assign_proxy!('hybrid-5511900000003', imported, account: account, pool: 'datacenter', digest: 'importado')
      .update!(origin: 'imported')
    isp = webshare_proxy(id: 50, address: '10.5.0.1')
    allow(webshare).to receive(:proxies).and_return([proxy, imported, isp])
    with_modified_env(WHATSAPP_PROXY_AUTO_MIGRATE: 'true') { WhatsappProxy::Assigner.new.for('hybrid-5511900000003') }
    expect(WhatsappProxy::Assignment.find_by!(session_name: 'hybrid-5511900000003')).to have_attributes(pool: 'isp', origin: 'assigned')
    allow(client).to receive(:get_session).and_return(remote(server: '10.0.0.3:6000', username: 'x'),
                                                      remote(server: '10.0.0.3:6000', status: 'STARTING'))
    stub_const('WhatsappProxy::SessionUpdater::HEALTH_ATTEMPTS', 1)

    described_class.perform_now('hybrid-5511900000003')

    expect(WhatsappProxy::Assignment.find_by!(session_name: 'hybrid-5511900000003'))
      .to have_attributes(pool: 'datacenter', origin: 'imported', proxy_address: '10.0.0.3', credential_digest: 'importado')
  end

  describe 'PUT and rollback both fail (HIGH): the table follows what the engine shows' do
    before do
      moved_from_old!
      stub_const('WhatsappProxy::SessionUpdater::HEALTH_ATTEMPTS', 1)
      allow(client).to receive(:update_session).and_raise(Waha::Client::Error, 'down')
    end

    it 'engine stayed on the OLD proxy → the table goes back to the old one (with its credential)' do
      allow(client).to receive(:get_session).and_return(remote(server: '10.0.0.9:6000', username: 'x'),
                                                        remote(server: '10.0.0.9:6000', username: 'x'))

      log = capture_log { described_class.perform_now(session) }

      expect(WhatsappProxy::Assignment.last).to have_attributes(proxy_address: '10.0.0.9', previous_proxy_address: nil, apply_failures: 1,
                                                                credential_digest: Webshare::Proxy.digest_for('x', 'senha-2'))
      expect(log).to include('[alerta] volta_falhou')
    end

    it 'engine ended on the NEW proxy → the table stays on it' do
      allow(client).to receive(:update_session).and_return({})
      allow(client).to receive(:update_session).with(session, config: hash_including('proxy' => hash_including('server' => '10.0.0.9:6000')))
                                               .and_raise(Waha::Client::Error, 'down')
      allow(client).to receive(:get_session).and_return(remote(server: '10.0.0.9:6000', username: 'x'),
                                                        remote(server: '10.0.0.2:6000', status: 'STARTING'),
                                                        remote(server: '10.0.0.2:6000'))

      described_class.perform_now(session)

      expect(WhatsappProxy::Assignment.last).to have_attributes(proxy_address: '10.0.0.2', previous_proxy_address: nil, apply_failures: 1,
                                                                credential_digest: proxy.credential_digest)
    end

    it 'engine unreadable → no credential, previous kept, convergence decides next round' do
      call = 0
      allow(client).to receive(:get_session) do
        call += 1
        raise Waha::Client::Error, 'down' if call > 1

        remote(server: '10.0.0.9:6000', username: 'x')
      end

      described_class.perform_now(session)

      expect(WhatsappProxy::Assignment.last).to have_attributes(proxy_address: '10.0.0.2', previous_proxy_address: '10.0.0.9',
                                                                credential_digest: nil, apply_failures: 1, apply_scheduled_at: nil)
    end
  end

  it 'clears the previous state when restoring is refused by validation (L1)' do
    moved_from_old!
    undone_by_engine!
    WhatsappProxy::Assignment.create!(session_name: 'outra', account_id: create(:account).id, pool: 'datacenter', webshare_proxy_id: '9',
                                      proxy_address: '10.0.0.9', proxy_port: 6000, assigned_at: Time.current)

    described_class.perform_now(session)

    expect(WhatsappProxy::Assignment.find_by!(session_name: session)).to have_attributes(pending?: true, previous_proxy_address: nil,
                                                                                         previous_pool: nil, apply_failures: 1)
  end

  it 'never runs twice at the same time and only releases its own lock (M5)' do
    Redis::Alfred.set(WhatsappProxy::SessionLock.key(session), 'outro-job', nx: true, ex: 60)
    allow(client).to receive(:get_session)

    described_class.perform_now(session)

    expect(client).not_to have_received(:get_session)
    expect(Redis::Alfred.get(WhatsappProxy::SessionLock.key(session))).to eq('outro-job')
  end

  it 'releases its own lock at the end' do
    allow(client).to receive(:get_session).and_return(remote(server: '10.0.0.2:6000'))

    described_class.perform_now(session)

    expect(Redis::Alfred.get(WhatsappProxy::SessionLock.key(session))).to be_nil
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
