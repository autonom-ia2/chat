require 'rails_helper'

describe WhatsappHybrid::RateLimit do
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:inbox) { channel.inbox }
  let!(:admin) { create(:user, account: inbox.account, role: :administrator) }
  let(:connection) do
    WhatsappHybrid::Connection.create!(account: inbox.account, inbox: inbox, session_name: "hybrid-#{SecureRandom.hex(3)}",
                                       status: 'connected', rate_limit_per_minute: 20)
  end

  def sends(origin, times)
    Array.new(times) { described_class.new(connection, origin).exceeded? }
  end

  it 'lets campaigns use at most 10 per minute even when the connection allows 20' do
    results = sends('campaign', 11)

    expect(results.first(10)).to all(be(false))
    expect(results.last).to be(true)
    expect(sends('human', 1)).to eq([false])
  end

  it 'halves the speed when WhatsApp warns about the limit and quarters it on the second warning' do
    WhatsappHybrid::Capping.new(connection).apply!('cappingStatus' => 'FIRST_WARNING', 'totalQuota' => 1000, 'usedQuota' => 640)
    expect(sends('human', 11).count(true)).to eq(1)

    WhatsappHybrid::Capping.new(connection).apply!('cappingStatus' => 'SECOND_WARNING', 'totalQuota' => 1000, 'usedQuota' => 900)
    expect(WhatsappHybrid::Capping.new(connection).rate_factor).to eq(0.25)
  end

  describe WhatsappHybrid::Capping do
    it 'warns the administrators once per state and cycle' do
      capping = described_class.new(connection)
      data = { 'cappingStatus' => 'FIRST_WARNING', 'totalQuota' => 1000, 'usedQuota' => 640, 'cycleStart' => 1, 'cycleEnd' => 1_790_000_000 }

      capping.apply!(data)
      capping.apply!(data.merge('usedQuota' => 700))
      capping.apply!(data.merge('cappingStatus' => 'CAPPED', 'usedQuota' => 700))

      avisos = Autonomia::Guide::Aviso.where(account: inbox.account, user: admin).order(:id)
      expect(avisos.map(&:gravidade)).to eq(%w[agir urgente])
      expect(avisos.last.texto).to include(inbox.name)
      expect(capping.current).to include('status' => 'CAPPED', 'used' => 700)
    end

    it 'does not warn on the normal state' do
      described_class.new(connection).apply!('cappingStatus' => 'NONE', 'totalQuota' => -1, 'usedQuota' => 0)

      expect(Autonomia::Guide::Aviso.count).to eq(0)
    end
  end

  describe WhatsappHybrid::Stats do
    it 'sums the last seven days by origin and outcome' do
      described_class.record(connection, origin: 'human', outcome: 'sent')
      described_class.record(connection, origin: 'human', outcome: 'sent')
      described_class.record(connection, origin: 'campaign', outcome: 'throttled')
      travel_to(8.days.ago) { described_class.record(connection, origin: 'human', outcome: 'sent') }

      summary = described_class.summary(connection)

      expect(summary['human']['sent']).to eq(2)
      expect(summary['campaign']['throttled']).to eq(1)
      expect(summary['bot']['sent']).to eq(0)
    end
  end

  describe 'hybrid inbox flag when Redis is unavailable' do
    it 'answers from the database instead of breaking the conversation list' do
      connection
      allow(Redis::Alfred).to receive(:get).and_raise(Redis::CannotConnectError)

      expect(WhatsappHybrid::Config.hybrid_inbox?(inbox.id)).to be(true)
    end
  end

  describe 'hybrid inbox flag' do
    it 'answers from cache and forgets it when the connection is created' do
      expect(WhatsappHybrid::Config.hybrid_inbox?(inbox.id)).to be(false)

      connection

      expect(WhatsappHybrid::Config.hybrid_inbox?(inbox.id)).to be(true)
    end
  end
end
