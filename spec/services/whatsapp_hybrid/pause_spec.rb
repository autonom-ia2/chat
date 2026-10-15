require 'rails_helper'

# #1487: pausar para a sessão no motor sem desvincular o aparelho; retomar religa sem QR. Enquanto pausada, nada religa
# a sessão sozinho e a parada não vira alerta de queda. Só 404 é "sem sessão"; outra falha do motor recusa o pedido.
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
                                      capping: {}, restart_session: {}, create_session: {})
    Redis::Alfred.delete(WhatsappProxy::SessionLock.key('hybrid-pause'))
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

    it 'does not save the pause nor stop anything when the engine cannot be read' do
      allow(client).to receive(:get_session).and_raise(Waha::Client::Timeout, 'timeout')

      expect { pause.pause! }.to raise_error(Waha::Client::Error)
      expect(client).not_to have_received(:stop_session)
      expect(connection.reload).not_to be_paused
    end

    it 'keeps the pause after a stop timeout only when the engine then shows the session stopped' do
      allow(client).to receive(:get_session).and_return(working, stopped, stopped)
      allow(client).to receive(:stop_session).and_raise(Waha::Client::Timeout, 'timeout')

      pause.pause!

      expect(connection.reload).to be_paused
    end

    it 'undoes the pause after a stop timeout when the session is still running' do
      allow(client).to receive(:get_session).and_return(working, working)
      allow(client).to receive(:stop_session).and_raise(Waha::Client::Timeout, 'timeout')

      expect { pause.pause! }.to raise_error(Waha::Client::Error)
      expect(connection.reload).not_to be_paused
    end

    it 'stops again when the pause is already saved but the session is running in the engine' do
      connection.update!(paused_at: 1.hour.ago, status: 'connected')
      allow(client).to receive(:get_session).and_return(working, stopped)

      pause.pause!

      expect(client).to have_received(:stop_session).with('hybrid-pause')
      expect(connection.reload).to be_paused
    end

    it 'keeps an existing pause when the engine refuses the new stop' do
      connection.update!(paused_at: 1.hour.ago, status: 'connected')
      allow(client).to receive(:get_session).and_return(working)
      allow(client).to receive(:stop_session).and_raise(Waha::Client::Error.new('boom', status: 500))

      expect { pause.pause! }.to raise_error(Waha::Client::Error)
      expect(connection.reload).to be_paused
    end

    it 'refuses while another change holds the session' do
      Redis::Alfred.set(WhatsappProxy::SessionLock.key('hybrid-pause'), 'other', ex: 60)
      allow(client).to receive(:get_session)

      expect { pause.pause! }.to raise_error(described_class::Busy)
      expect(client).not_to have_received(:get_session)
      expect(connection.reload).not_to be_paused
    end
  end

  # A pausa vale mesmo com o estado ainda "conectado" (o aviso do motor chega antes da consulta de volta).
  describe 'engine events on a paused connection' do
    before do
      connection.update!(paused_at: Time.current, status: 'connected')
      allow(WhatsappHybrid::DownAlert).to receive(:new).and_call_original
      allow(WhatsappProxy::Health).to receive(:record_drop!)
    end

    %w[STOPPED FAILED STARTING].each do |engine_status|
      it "does not alert the admins nor count a proxy drop on #{engine_status}" do
        WhatsappHybrid::WebhookEventJob.perform_now(connection.id, 'session.status', { 'status' => engine_status })

        expect(WhatsappHybrid::DownAlert).not_to have_received(:new)
        expect(WhatsappProxy::Health).not_to have_received(:record_drop!)
        expect(connection.reload.down_alerted_at).to be_nil
      end
    end

    it 'still counts the drop of a connection that is not paused (control)' do
      connection.update!(paused_at: nil)

      WhatsappHybrid::WebhookEventJob.perform_now(connection.id, 'session.status', { 'status' => 'FAILED' })

      expect(WhatsappProxy::Health).to have_received(:record_drop!).with('hybrid-pause')
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

    it 'keeps the pause, recreates nothing and keeps the proxy assignment when the engine cannot be read' do
      assignment = WhatsappProxy::Assignment.create!(session_name: 'hybrid-pause', account_id: connection.account_id,
                                                     pool: 'isp', webshare_proxy_id: '1', proxy_address: '10.0.0.1',
                                                     proxy_port: 6000, assigned_at: Time.current)
      allow(client).to receive(:get_session).and_raise(Waha::Client::Error.new('bad gateway', status: 502))

      expect { pause.resume! }.to raise_error(Waha::Client::Error)
      expect(client).not_to have_received(:create_session)
      expect(client).not_to have_received(:start_session)
      expect(connection.reload).to be_paused
      expect(WhatsappProxy::Assignment.exists?(assignment.id)).to be(true)
    end

    it 'keeps the pause and returns the error when the engine refuses to recreate the session' do
      allow(client).to receive(:get_session).and_raise(Waha::Client::NotFound.new('404', status: 404))
      allow(client).to receive(:create_session).and_raise(Waha::Client::Error.new('boom', status: 500))

      expect { pause.resume! }.to raise_error(Waha::Client::Error)
      expect(connection.reload).to be_paused
    end

    it 'recreates the session (with a QR code) only when the engine no longer has it' do
      calls = 0
      allow(client).to receive(:get_session) do
        calls += 1
        raise Waha::Client::NotFound.new('404', status: 404) if calls == 1

        calls == 2 ? nil : { 'status' => 'SCAN_QR_CODE' }
      end

      pause.resume!

      expect(client).to have_received(:create_session)
      expect(connection.reload).not_to be_paused
    end
  end

  it 'reconnect! (new QR code) on a paused session starts it first, then logs out, and clears the pause' do
    connection.update!(paused_at: Time.current, status: 'disconnected')
    allow(Kernel).to receive(:sleep)
    allow(client).to receive(:get_session).and_return(stopped, working)
    expect(client).to receive(:start_session).with('hybrid-pause').ordered
    expect(client).to receive(:logout_session).with('hybrid-pause').ordered

    manager.reconnect!

    expect(connection.reload).not_to be_paused
  end
end
