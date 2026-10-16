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

  it 'gives up at the time limit when the session never comes up, and says so' do
    # Relógio: início 0; antes da espera 0; depois da espera 4 (faltam 2 s, a consulta usa 2 s, não 3); na volta
    # seguinte 6 (acabou o prazo).
    allow(wake).to receive(:monotonic_now).and_return(0, 0, 4, 6)
    allow(client).to receive(:get_session).and_return({ 'status' => 'STOPPED' }, { 'status' => 'STARTING' })
    allow(Rails.logger).to receive(:warn)

    expect(wake.call).to be(false)
    # 1 leitura antes do start e 1 só consulta no laço: o prazo encerrou antes do MAX_TRIES.
    expect(client).to have_received(:get_session).twice
    expect(client).to have_received(:get_session).with('hybrid-wake', timeout: 2)
    expect(Rails.logger).to have_received(:warn).with(/não subiu/)
  end

  it 'asks to try again when the engine does not answer the start (timeout)' do
    allow(client).to receive(:get_session).and_return({ 'status' => 'STOPPED' })
    allow(client).to receive(:start_session).and_raise(Waha::Client::Timeout, 'timeout')
    allow(Rails.logger).to receive(:warn)

    expect(wake.call).to be(false)
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
