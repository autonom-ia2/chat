require 'rails_helper'

RSpec.describe WhatsappProxy::Health do
  let(:session) { 'hybrid-551142155355' }

  before do
    %w[unstable_rounds drops unstable_swap scan_qr].each { |key| Redis::Alfred.delete("whatsapp_proxy:#{key}:#{session}") }
    %w[isp baseline].each { |scope| Redis::Alfred.delete(WhatsappProxy::Outage.episode_key(scope)) }
  end

  it 'reports unstable only after UNSTABLE_ROUNDS rounds off WORKING in a row' do
    expect(described_class.observe!(session, 'STARTING')).to be_nil
    expect(described_class.observe!(session, 'FAILED')).to eq(:unstable)
  end

  it 'starts over when the session is back to WORKING' do
    described_class.observe!(session, 'STARTING')
    described_class.observe!(session, 'WORKING')

    expect(described_class.observe!(session, 'STARTING')).to be_nil
  end

  it 'ignores STOPPED and treats SCAN_QR_CODE as an unlinked device, reported once a day' do
    described_class.observe!(session, 'STARTING')

    expect(described_class.observe!(session, 'STOPPED')).to be_nil
    expect(described_class.observe!(session, 'SCAN_QR_CODE')).to eq(:scan_qr)
    expect(described_class.observe!(session, 'SCAN_QR_CODE')).to be_nil
    expect(described_class.observe!(session, 'STARTING')).to be_nil
  end

  it 'counts drops seen by the Hybrid webhook (connected → connecting), not QR' do
    channel = create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
    connection = WhatsappHybrid::Connection.create!(account: channel.account, inbox: channel.inbox, session_name: session,
                                                    status: 'connected', connected_phone: '1')
    manager = WhatsappHybrid::SessionManager.new(connection, client: instance_double(Waha::Client))

    manager.apply_status!('connecting')
    manager.apply_status!('connected')
    manager.apply_status!('awaiting_scan')

    expect(described_class.drops(session)).to eq(1)
  end

  it 'never swaps when Redis is down' do
    allow(Redis::Alfred).to receive(:incr).and_raise(Redis::CannotConnectError)
    allow(Redis::Alfred).to receive(:get).and_raise(Redis::CannotConnectError)

    2.times { expect(described_class.observe!(session, 'STARTING')).to be_nil }
  end
end
