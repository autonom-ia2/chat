require 'rails_helper'

# chat#1480: o retrato do limite temporário de conversas novas que o motor informa.
describe WhatsappHybrid::Timelock do
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:connection) do
    WhatsappHybrid::Connection.create!(account: channel.account, inbox: channel.inbox, session_name: 'hybrid-timelock',
                                       status: 'connected', connected_phone: channel.phone_number.delete('^0-9'))
  end
  let(:timelock) { described_class.new(connection) }

  before { Redis::Alfred.delete(timelock.key) }

  it 'has no limit before the engine says anything' do
    expect(timelock.active?).to be(false)
    expect(timelock.fresh?).to be(false)
    expect(timelock.payload).to eq(active: false, ends_at: nil)
  end

  it 'reports the active limit and when it ends' do
    ends_at = 6.hours.from_now.to_i

    timelock.apply!('enforcementType' => 'RESTRICT_ALL_COMPANIONS', 'isActive' => true, 'timeEnforcementEnds' => ends_at)

    expect(timelock.payload).to eq(active: true, ends_at: ends_at)
    expect(timelock.fresh?).to be(true)
  end

  it 'stops reporting once the end has passed, even without a new answer from the engine' do
    timelock.apply!('isActive' => true, 'timeEnforcementEnds' => 1.minute.ago.to_i)

    expect(timelock.payload).to eq(active: false, ends_at: nil)
  end

  it 'keeps an active limit that has no end' do
    timelock.apply!('isActive' => true, 'timeEnforcementEnds' => nil)

    expect(timelock.payload).to eq(active: true, ends_at: nil)
  end

  it 'treats an inactive or empty answer as no limit' do
    timelock.apply!('enforcementType' => 'DEFAULT', 'isActive' => false, 'timeEnforcementEnds' => nil)
    expect(timelock.active?).to be(false)

    timelock.apply!(nil)
    expect(timelock.active?).to be(false)
  end

  it 'asks the engine again only after the snapshot gets old' do
    client = instance_double(Waha::Client, get_session: { 'status' => 'WORKING', 'me' => { 'id' => "#{connection.connected_phone}@c.us" } },
                                           update_session: {}, capping: {}, timelock: { 'isActive' => false })
    manager = WhatsappHybrid::SessionManager.new(connection, client: client)

    manager.refresh!
    manager.refresh!
    expect(client).to have_received(:timelock).once

    travel_to(2.minutes.from_now) { manager.refresh! }
    expect(client).to have_received(:timelock).twice
  end
end
