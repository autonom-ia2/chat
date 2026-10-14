require 'rails_helper'

RSpec.describe WhatsappProxy::SessionUpdater do
  let(:client) { instance_double(Waha::Client, update_session: {}) }
  let(:sleeps) { [] }
  let(:updater) { described_class.new(client: client, sleeper: ->(seconds) { sleeps << seconds }, health_attempts: 3, health_interval: 5) }
  let(:proxy) { webshare_proxy(id: 2, address: '10.0.0.2') }
  let(:old_config) do
    { 'ignore' => { 'groups' => true }, 'metadata' => { 'x' => 1 }, 'proxy' => { 'server' => '10.0.0.1:6000', 'username' => 'old' } }
  end
  let(:apps) { [{ 'id' => 'app_1', 'app' => 'chatwoot' }, { 'id' => 'br_1', 'app' => 'brazilian-phone-numbers' }] }
  let(:before) { { 'status' => 'WORKING', 'me' => { 'id' => '551199999999@c.us' }, 'config' => old_config } }

  def after(status: 'WORKING', number: '551199999999@c.us', server: '10.0.0.2:6000')
    { 'status' => status, 'me' => { 'id' => number }, 'config' => old_config.merge('proxy' => { 'server' => server }) }
  end

  before { allow(client).to receive(:list_apps).and_return(apps) }

  %w[SCAN_QR_CODE STOPPED].each do |status|
    it "refuses to touch a session in #{status} (no PUT)" do
      allow(client).to receive(:get_session).and_return(before.merge('status' => status))

      expect(updater.apply!('5511999999999', proxy)).to eq(:refused)
      expect(client).not_to have_received(:update_session)
    end
  end

  it 'reads the engine with a short timeout' do
    allow(client).to receive(:get_session).and_return(before, after)

    updater.apply!('5511999999999', proxy)

    expect(client).to have_received(:get_session).with('5511999999999', timeout: described_class::READ_TIMEOUT).twice
  end

  it 'swaps only the proxy block, never sends apps, and confirms number, apps and proxy' do
    allow(client).to receive(:get_session).and_return(before, after(status: 'STARTING'), after)

    expect(updater.apply!('5511999999999', proxy)).to eq(:applied)

    expected = old_config.merge('proxy' => { 'server' => '10.0.0.2:6000', 'username' => 'user-2', 'password' => 'senha-2' })
    expect(client).to have_received(:update_session).with('5511999999999', config: expected).once
    expect(sleeps).to eq([5])
  end

  it 'compares the connected number (me.id), not the session name' do
    allow(client).to receive(:get_session).and_return(before, after(number: '5511888888888@c.us'))

    expect(updater.apply!('5511999999999', proxy)).to eq(:rolled_back)
    expect(client).to have_received(:update_session).with('5511999999999', config: old_config)
  end

  it 'rolls back when the session does not come back WORKING' do
    allow(client).to receive(:get_session).and_return(before, after(status: 'STARTING'))

    log = capture_log { expect(updater.apply!('5511999999999', proxy)).to eq(:rolled_back) }

    expect(client).to have_received(:update_session).with('5511999999999', config: old_config)
    expect(log).to include('session_did_not_return_to_working')
    expect(log).not_to include('senha-2')
  end

  it 'rolls back when the engine lost an app' do
    allow(client).to receive(:get_session).and_return(before, after)
    allow(client).to receive(:list_apps).and_return(apps, apps.first(1))

    expect(updater.apply!('5511999999999', proxy)).to eq(:rolled_back)
  end

  it 'rolls back when the proxy was not saved' do
    allow(client).to receive(:get_session).and_return(before, after(server: '10.0.0.1:6000'))

    expect(updater.apply!('5511999999999', proxy)).to eq(:rolled_back)
  end

  it 'accepts a session that had no number yet (broken by a dead IP) once it is WORKING with the new proxy' do
    allow(client).to receive(:get_session).and_return(before.merge('status' => 'FAILED', 'me' => nil), after(number: nil))

    expect(updater.apply!('5511999999999', proxy)).to eq(:applied)
  end

  it 'rolls back when the PUT itself fails' do
    allow(client).to receive(:get_session).and_return(before)
    allow(client).to receive(:update_session).and_raise(Waha::Client::Error, 'down').once
    allow(client).to receive(:update_session).with('5511999999999', config: old_config).and_return({})

    expect(updater.apply!('5511999999999', proxy)).to eq(:rolled_back)
  end
end
