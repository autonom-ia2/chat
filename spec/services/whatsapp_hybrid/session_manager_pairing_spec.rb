require 'rails_helper'

# chat#1486: a prova de "o aparelho já conversou" conta a partir do pareamento atual. Só pareamento novo grava a hora.
describe WhatsappHybrid::SessionManager do
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:phone) { channel.phone_number.delete('^0-9') }
  let(:connection) do
    WhatsappHybrid::Connection.create!(account: channel.account, inbox: channel.inbox, session_name: 'hybrid-pairing',
                                       status: 'pending')
  end
  let(:manager) { described_class.new(connection, client: instance_double(Waha::Client)) }
  let(:earlier) { Time.zone.parse('2026-10-12 09:00:00 UTC') }

  around { |example| travel_to(Time.zone.parse('2026-10-13 18:20:00 UTC')) { example.run } }

  before { Redis::Alfred.delete(WhatsappHybrid::ReachOut.paired_at_key(connection)) }

  def paired_at
    WhatsappHybrid::ReachOut.paired_at(connection)
  end

  it 'records the pairing when the QR code is read' do
    connection.update!(status: 'awaiting_scan')

    manager.apply_status!('connected', phone: phone)

    expect(paired_at).to eq(Time.current.change(usec: 0))
  end

  it 'records the first pairing, when there was no device yet' do
    manager.apply_status!('connected', phone: phone)

    expect(paired_at).to eq(Time.current.change(usec: 0))
  end

  it 'records the pairing after a reconnect, which clears the device number' do
    connection.update!(status: 'connecting', connected_phone: nil)

    manager.apply_status!('connected', phone: phone)

    expect(paired_at).to eq(Time.current.change(usec: 0))
  end

  it 'keeps the pairing time when the session was already connected (refresh or webhook)' do
    connection.update!(status: 'connected', connected_phone: phone)
    WhatsappHybrid::ReachOut.paired!(connection, at: earlier)

    manager.apply_status!('connected', phone: phone)

    expect(paired_at).to eq(earlier)
  end

  it 'keeps the pairing time when the websocket reconnects by itself with the device still there' do
    connection.update!(status: 'connecting', connected_phone: phone)
    WhatsappHybrid::ReachOut.paired!(connection, at: earlier)

    manager.apply_status!('connected', phone: phone)

    expect(paired_at).to eq(earlier)
  end

  it 'does not record anything while the session is not connected' do
    connection.update!(status: 'awaiting_scan')

    manager.apply_status!('connecting')

    expect(paired_at).to be_nil
  end
end
