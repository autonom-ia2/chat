require 'rails_helper'

RSpec.describe WhatsappProxy::Health do
  let(:session) { 'hybrid-551142155355' }

  around { |example| with_modified_env(WHATSAPP_PROXY_ENABLED: 'true') { example.run } }

  before do
    %w[unstable_rounds drops unstable_swap].each { |key| Redis::Alfred.delete("whatsapp_proxy:#{key}:#{session}") }
    %w[isp baseline].each { |scope| Redis::Alfred.delete(WhatsappProxy::Outage.episode_key(scope)) }
  end

  it 'reports unstable after UNSTABLE_ROUNDS rounds off WORKING, counting from a drop out of WORKING' do
    expect(described_class.observe!(session, 'STARTING', previous: 'WORKING')).to be_nil
    expect(described_class.observe!(session, 'FAILED', previous: 'STARTING')).to eq(:unstable)
  end

  it 'never counts a session that was not WORKING before (old FAILED)' do
    3.times { expect(described_class.observe!(session, 'FAILED', previous: 'FAILED')).to be_nil }
    expect(described_class.observe!(session, 'FAILED', previous: nil)).to be_nil
    expect(described_class.rounds(session)).to eq(0)
  end

  it 'starts over when the session is back to WORKING' do
    described_class.observe!(session, 'STARTING', previous: 'WORKING')
    described_class.observe!(session, 'WORKING', previous: 'STARTING')

    expect(described_class.observe!(session, 'STARTING', previous: 'STOPPED')).to be_nil
    expect(described_class.rounds(session)).to eq(0)
  end

  it 'lets a seeded session (end of a long outage) count from the first round' do
    described_class.seed!(session)

    expect(described_class.observe!(session, 'STARTING', previous: 'STARTING')).to eq(:unstable)
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
    allow(Redis::Alfred).to receive_messages(incr: nil, get: nil)
    allow(Redis::Alfred).to receive(:incr).and_raise(Redis::CannotConnectError)
    allow(Redis::Alfred).to receive(:get).and_raise(Redis::CannotConnectError)

    expect(described_class.observe!(session, 'STARTING', previous: 'WORKING')).to be_nil
    expect(described_class.observe!(session, 'STARTING', previous: 'STARTING')).to be_nil
  end
end
