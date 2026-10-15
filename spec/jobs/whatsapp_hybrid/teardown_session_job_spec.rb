require 'rails_helper'

RSpec.describe WhatsappHybrid::TeardownSessionJob do
  let(:client) { instance_double(Waha::Client) }

  before do
    allow(Waha::Client).to receive(:new).and_return(client)
    allow(client).to receive(:get_session).and_return({ 'status' => 'WORKING' })
  end

  it 'logs out and deletes the session' do
    allow(client).to receive(:logout_session)
    allow(client).to receive(:delete_session)

    described_class.perform_now('hybrid-1')

    expect(client).to have_received(:delete_session).with('hybrid-1')
  end

  it 'still deletes when logout fails' do
    allow(client).to receive(:logout_session).and_raise(Waha::Client::Error, 'boom')
    allow(client).to receive(:delete_session)

    described_class.perform_now('hybrid-1')

    expect(client).to have_received(:delete_session).with('hybrid-1')
  end

  it 'treats a session the engine no longer has as done' do
    allow(client).to receive(:logout_session).and_raise(Waha::Client::NotFound, '404')
    allow(client).to receive(:delete_session).and_raise(Waha::Client::NotFound, '404')

    expect { described_class.perform_now('hybrid-1') }.not_to have_enqueued_job(described_class)
  end

  it 'frees the Webshare IP once the session is gone (#1516), but not while the engine is down' do
    WhatsappProxy::Assignment.create!(session_name: 'hybrid-1', account_id: create(:account).id, pool: 'isp',
                                      webshare_proxy_id: '1', proxy_address: '10.0.0.1',
                                      proxy_port: 6000, assigned_at: Time.current)
    allow(client).to receive(:logout_session)
    allow(client).to receive(:delete_session).and_raise(Waha::Client::Error, 'down')

    described_class.perform_now('hybrid-1')
    expect(WhatsappProxy::Assignment.count).to eq(1)

    allow(client).to receive(:delete_session)
    described_class.perform_now('hybrid-1')
    expect(WhatsappProxy::Assignment.count).to eq(0)
  end

  it 'tries again later when the engine is down' do
    allow(client).to receive(:logout_session).and_raise(Waha::Client::Error, 'down')
    allow(client).to receive(:delete_session).and_raise(Waha::Client::Error, 'WAHA DELETE -> 502')

    expect { described_class.perform_now('hybrid-1') }.to have_enqueued_job(described_class).with('hybrid-1')
  end

  context 'with a stopped session (WhatsApp API paused, #1487)' do
    it 'starts it first and logs out only once it is up, so the phone really drops the device' do
      allow(client).to receive(:get_session).and_return({ 'status' => 'STOPPED' })
      allow(client).to receive_messages(start_session: {}, logout_session: {}, delete_session: {})

      expect { described_class.perform_now('hybrid-1') }.to have_enqueued_job(described_class).with('hybrid-1')
      expect(client).to have_received(:start_session).with('hybrid-1')
      expect(client).not_to have_received(:logout_session)

      allow(client).to receive(:get_session).and_return({ 'status' => 'WORKING' })
      described_class.perform_now('hybrid-1')

      expect(client).to have_received(:logout_session).with('hybrid-1')
      expect(client).to have_received(:delete_session).with('hybrid-1')
    end

    it 'logs out and deletes anyway when the session never comes up' do
      allow(client).to receive_messages(logout_session: {}, delete_session: {})

      described_class.perform_now('hybrid-1', wake: false)

      expect(client).not_to have_received(:get_session)
      expect(client).to have_received(:delete_session).with('hybrid-1')
    end

    it 'gives up waking after the last attempt and still logs out and deletes' do
      allow(client).to receive(:get_session).and_return({ 'status' => 'STARTING' })
      allow(client).to receive_messages(start_session: {}, logout_session: {}, delete_session: {})

      perform_enqueued_jobs { described_class.perform_later('hybrid-1') }

      expect(client).to have_received(:get_session).exactly(described_class::WAKE_ATTEMPTS).times
      expect(client).not_to have_received(:start_session)
      expect(client).to have_received(:logout_session).with('hybrid-1').once
      expect(client).to have_received(:delete_session).with('hybrid-1').once
    end
  end
end
