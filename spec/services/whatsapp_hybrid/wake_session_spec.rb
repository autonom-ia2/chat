require 'rails_helper'

# #1487: religar a sessão parada (pausada) antes do logout, com teto curto no reconectar da aba.
describe WhatsappHybrid::WakeSession do
  let(:client) { instance_double(Waha::Client) }
  let(:wake) { described_class.new(client, 'hybrid-wake') }

  before do
    allow(Kernel).to receive(:sleep)
    allow(client).to receive(:start_session)
  end

  it 'starts a stopped session with a short timeout and returns true once it is up' do
    allow(client).to receive(:get_session).and_return({ 'status' => 'STOPPED' }, { 'status' => 'STARTING' },
                                                      { 'status' => 'WORKING' })

    expect(wake.call).to be(true)
    expect(client).to have_received(:start_session).with('hybrid-wake', timeout: described_class::STEP_TIMEOUT)
    expect(client).to have_received(:get_session).with('hybrid-wake', timeout: described_class::STEP_TIMEOUT).at_least(:once)
  end

  it 'counts a session asking for the QR code as up (the reconnect flow takes it from there)' do
    allow(client).to receive(:get_session).and_return({ 'status' => 'STOPPED' }, { 'status' => 'SCAN_QR_CODE' })

    expect(wake.call).to be(true)
  end

  it 'gives up within the limit when the session never comes up, and says so' do
    allow(client).to receive(:get_session).and_return({ 'status' => 'STOPPED' }, { 'status' => 'STARTING' })
    allow(Rails.logger).to receive(:warn)

    expect(wake.call).to be(false)
    expect(client).to have_received(:get_session).at_most(described_class::MAX_TRIES + 1).times
    expect(Rails.logger).to have_received(:warn).with(/não subiu/)
  end

  it 'treats an engine that stops answering as still starting' do
    calls = 0
    allow(client).to receive(:get_session) do
      calls += 1
      raise Waha::Client::Timeout, 'timeout' if calls > 1

      { 'status' => 'STOPPED' }
    end

    expect(wake.call).to be(false)
  end

  it 'ends the wait when the engine no longer has the session (the reconnect recreates it)' do
    calls = 0
    allow(client).to receive(:get_session) do
      calls += 1
      raise Waha::Client::NotFound.new('404', status: 404) if calls > 1

      { 'status' => 'STOPPED' }
    end

    expect(wake.call).to be(true)
    expect(calls).to eq(2)
  end

  it 'does nothing for a session that is already up' do
    allow(client).to receive(:get_session).and_return({ 'status' => 'WORKING' })

    expect(wake.call).to be(true)
    expect(client).not_to have_received(:start_session)
  end
end
