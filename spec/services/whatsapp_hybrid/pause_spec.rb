require 'rails_helper'

# #1487: pausar para a sessão no motor sem desvincular o aparelho; retomar religa sem QR. Enquanto pausada, nada religa
# a sessão sozinho e a parada não vira alerta de queda.
describe WhatsappHybrid::Pause do
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:phone) { channel.phone_number.delete('^0-9') }
  let(:client) { instance_double(Waha::Client) }
  let(:pause) { described_class.new(connection, client: client) }
  let(:manager) { WhatsappHybrid::SessionManager.new(connection, client: client) }
  let(:working) { { 'status' => 'WORKING', 'me' => { 'id' => "#{phone}@c.us" } } }
  let(:stopped) { { 'status' => 'STOPPED', 'me' => { 'id' => "#{phone}@c.us" } } }
  let(:connection) do
    WhatsappHybrid::Connection.create!(account: channel.account, inbox: channel.inbox, session_name: 'hybrid-pause',
                                       status: 'connected', connected_phone: phone, risk_accepted_at: Time.current,
                                       status_checked_at: Time.current)
  end

  before do
    allow(client).to receive_messages(stop_session: {}, start_session: {}, logout_session: {}, update_session: {},
                                      capping: {}, restart_session: {})
    allow(WhatsappHybrid::DownAlert).to receive(:new).and_call_original
    allow(WhatsappProxy::Health).to receive(:record_drop!)
  end

  describe '#pause!' do
    it 'stops the session without logging out and keeps the device number' do
      allow(client).to receive(:get_session).and_return(working, stopped)

      pause.pause!

      expect(client).to have_received(:stop_session).with('hybrid-pause')
      expect(client).not_to have_received(:logout_session)
      expect(connection.reload).to have_attributes(status: 'disconnected', connected_phone: phone)
      expect(connection).to be_paused
    end

    it 'does not alert the admins nor count a proxy drop' do
      allow(client).to receive(:get_session).and_return(working, stopped)

      pause.pause!
      manager.apply_status!('connecting')

      expect(WhatsappHybrid::DownAlert).not_to have_received(:new)
      expect(WhatsappProxy::Health).not_to have_received(:record_drop!)
      expect(connection.reload.down_alerted_at).to be_nil
    end

    it 'never rewrites the session config while paused (a rewrite restarts it in the engine)' do
      allow(client).to receive(:get_session).and_return(working, stopped)

      pause.pause!

      expect(client).not_to have_received(:update_session)
    end

    it 'undoes the pause when the engine refuses to stop' do
      allow(client).to receive(:get_session).and_return(working)
      allow(client).to receive(:stop_session).and_raise(Waha::Client::Error.new('boom', status: 500))

      expect { pause.pause! }.to raise_error(Waha::Client::Error)
      expect(connection.reload).not_to be_paused
    end

    it 'keeps the pause when the engine does not answer (safe side: everything through the official API)' do
      allow(client).to receive(:get_session).and_return(working, stopped)
      allow(client).to receive(:stop_session).and_raise(Waha::Client::Timeout, 'timeout')

      pause.pause!

      expect(connection.reload).to be_paused
    end
  end

  describe 'while paused' do
    before { connection.update!(paused_at: Time.current, status: 'disconnected') }

    it 'ensure_session! does not start a stopped session' do
      allow(client).to receive(:get_session).and_return(stopped)

      manager.ensure_session!

      expect(client).not_to have_received(:start_session)
      expect(connection.reload).to be_paused
    end

    it 'ensure_session! does not recreate a session missing in the engine' do
      allow(client).to receive(:get_session).and_return(nil)
      allow(client).to receive(:create_session)

      manager.ensure_session!

      expect(client).not_to have_received(:create_session)
    end

    it 'refresh! only reads: no start, no config write' do
      allow(client).to receive(:get_session).and_return(stopped)

      expect(manager.refresh!).to eq('disconnected')
      expect(client).not_to have_received(:start_session)
      expect(client).not_to have_received(:update_session)
    end

    it 'does not ask the engine for a QR code' do
      allow(client).to receive(:qr_value)

      expect(manager.qr).to be_nil
      expect(client).not_to have_received(:qr_value)
    end
  end

  describe '#resume!' do
    before { connection.update!(paused_at: Time.current, status: 'disconnected') }

    it 'starts the same session, without a new QR code, and clears the pause' do
      allow(client).to receive(:get_session).and_return(stopped, working)

      pause.resume!

      expect(client).to have_received(:start_session).with('hybrid-pause')
      expect(client).not_to have_received(:logout_session)
      expect(connection.reload).to have_attributes(status: 'connected', paused_at: nil)
    end

    it 'falls into the normal QR flow when WhatsApp unlinked the device meanwhile' do
      allow(client).to receive(:get_session).and_return(stopped, { 'status' => 'SCAN_QR_CODE' })

      pause.resume!

      expect(connection.reload).to have_attributes(status: 'awaiting_scan', paused_at: nil)
    end

    it 'keeps the pause when the engine refuses to start' do
      allow(client).to receive(:get_session).and_return(stopped)
      allow(client).to receive(:start_session).and_raise(Waha::Client::Error.new('boom', status: 500))

      expect { pause.resume! }.to raise_error(Waha::Client::Error)
      expect(connection.reload).to be_paused
    end
  end

  it 'reconnect! (new QR code) clears the pause' do
    connection.update!(paused_at: Time.current, status: 'disconnected')
    allow(client).to receive(:get_session).and_return(stopped)

    manager.reconnect!

    expect(client).to have_received(:logout_session).with('hybrid-pause')
    expect(connection.reload).not_to be_paused
  end
end
