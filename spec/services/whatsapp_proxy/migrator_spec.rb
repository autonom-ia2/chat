require 'rails_helper'

RSpec.describe WhatsappProxy::Migrator do
  let(:account) { create(:account) }
  let(:session) { '5511900000001' }
  let(:proxy) { webshare_proxy(id: 2, address: '10.0.0.2') }
  let(:client) { instance_double(Waha::Client) }
  let(:updater) { instance_double(WhatsappProxy::SessionUpdater) }
  let(:assigner) do
    WhatsappProxy::Assigner.new(engine: instance_double(Waha::Client, list_sessions: []),
                                pools: { datacenter: fake_pool('datacenter', [proxy]), isp: fake_pool('isp', []) })
  end
  let(:migrator) { described_class.new(client: client, assigner: assigner, updater: updater) }

  around do |example|
    with_modified_env(WHATSAPP_PROXY_ENABLED: 'true', WEBSHARE_DATACENTER_PROXY_ADDRESSES: '10.0.0.2') { example.run }
  end

  before do
    Redis::Alfred.delete(WhatsappProxy::SessionLock.key(session))
    waha_session!(session, account)
    allow(client).to receive(:timelock).and_return({ 'isActive' => false })
  end

  it 'migrates one existing session: assigns, applies and records it' do
    allow(updater).to receive(:apply!).with(session, proxy).and_return(:applied)

    result = migrator.call(session)

    expect(result.outcome).to eq(:applied)
    expect(WhatsappProxy::Assignment.find_by!(session_name: session).credential_digest).to eq(proxy.credential_digest)
  end

  it 'refuses while WhatsApp restricts new conversations (/timelock), without touching anything' do
    allow(client).to receive(:timelock).and_return({ 'isActive' => true })
    allow(updater).to receive(:apply!)

    expect(migrator.call(session).outcome).to eq(:refused)
    expect(updater).not_to have_received(:apply!)
    expect(WhatsappProxy::Assignment.count).to eq(0)
  end

  it 'refuses when the timelock cannot be checked' do
    allow(client).to receive(:timelock).and_raise(Waha::Client::Error, 'down')

    expect(migrator.call(session).outcome).to eq(:refused)
  end

  it 'refuses a session that already has an assignment' do
    assign_proxy!(session, proxy, account: account)

    expect(migrator.call(session).detail).to eq('sessão já tem atribuição')
  end

  it 'drops the assignment when the change is undone, leaving the session as it was' do
    allow(updater).to receive(:apply!).and_return(:rolled_back)

    expect(migrator.call(session).outcome).to eq(:rolled_back)
    expect(WhatsappProxy::Assignment.count).to eq(0)
  end

  it 'never leaves an orphan assignment when the change blows up halfway (HIGH2)' do
    allow(updater).to receive(:apply!).and_raise(StandardError, 'boom')

    expect { migrator.call(session) }.to raise_error(StandardError, 'boom')
    expect(WhatsappProxy::Assignment.count).to eq(0)
  end

  it 'never leaves an orphan assignment on Ctrl-C (Interrupt) either (HIGH2)' do
    allow(updater).to receive(:apply!).and_raise(Interrupt)

    expect { migrator.call(session) }.to raise_error(Interrupt)
    expect(WhatsappProxy::Assignment.count).to eq(0)
    expect(Redis::Alfred.get(WhatsappProxy::SessionLock.key(session))).to be_nil
  end

  it 'keeps the table on the new proxy when the rollback failed (engine left on it) (M2)' do
    allow(updater).to receive(:apply!).and_return(:rollback_failed)

    expect(migrator.call(session).outcome).to eq(:rollback_failed)
    expect(WhatsappProxy::Assignment.find_by!(session_name: session)).to have_attributes(proxy_address: '10.0.0.2', apply_failures: 1)
  end

  it 'refuses while another proxy change of the session holds the lock (M4)' do
    Redis::Alfred.set(WhatsappProxy::SessionLock.key(session), 'apply-job', nx: true, ex: 60)
    allow(updater).to receive(:apply!)

    expect(migrator.call(session).outcome).to eq(:refused)
    expect(updater).not_to have_received(:apply!)
    expect(WhatsappProxy::Assignment.count).to eq(0)
  end

  it 'refuses while the feature is off' do
    with_modified_env(WHATSAPP_PROXY_ENABLED: nil) { expect(migrator.call(session).outcome).to eq(:refused) }
  end
end
