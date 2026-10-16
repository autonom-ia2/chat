require 'rails_helper'

# chat#1709 (fase 2): a capacidade do motor vem do cache, que só o job do cron preenche.
RSpec.describe Waha::EngineCapabilities do
  let(:engine) { 'https://waha.example/' }
  let(:url) { 'https://waha.example/api/server/version' }
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }

  around { |example| with_modified_env(WAHA_RICH_NATIVE_ENGINES: ' https://waha.example , https://outro.example/ ') { example.run } }

  before { allow(Rails).to receive(:cache).and_return(cache) }

  def version(autonomia)
    stub_request(:get, url).to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                                      body: { version: '2026.9.2', engine: 'GOWS', autonomia: autonomia }.compact.to_json)
  end

  it 'lists the engines with the trailing slash and matches the webhook by prefix, slash included' do
    expect(described_class.engines).to eq(%w[https://waha.example/ https://outro.example/])
    expect(described_class.engine_for('https://waha.example/webhooks/chatwoot/1')).to eq(engine)
    expect(described_class.engine_for('https://waha.example.evil.com/webhooks')).to be_nil
    expect(described_class.engine_for('https://waha.example')).to be_nil
    expect(with_modified_env(WAHA_RICH_NATIVE_ENGINES: '') { described_class.engine_for('https://waha.example/x') }).to be_nil
  end

  it 'is empty (text) with nothing in the cache, without asking the engine' do
    expect(described_class.types(engine)).to eq([])
    expect(described_class.types(nil)).to eq([])
    expect(a_request(:get, url)).not_to have_been_made
  end

  it 'reads what the refresh wrote; options only with list_reply' do
    version({ patch: 'c2y-rich-1', rich_native: %w[options location contact carousel], list_reply: true })
    described_class.refresh!(engine)
    expect(described_class.types(engine)).to eq(%w[options location contact])

    version({ patch: 'c2y-rich-1', rich_native: %w[options location], list_reply: false })
    described_class.refresh!(engine)
    expect(described_class.types(engine)).to eq(%w[location])

    version(nil)
    described_class.refresh!(engine)
    expect(described_class.types(engine)).to eq([])
  end

  it 'keeps the previous value while the engine fails, until it expires' do
    version({ rich_native: %w[location], list_reply: true })
    described_class.refresh!(engine)

    stub_request(:get, url).to_return(status: 500, body: 'boom')
    described_class.refresh!(engine)
    stub_request(:get, url).to_timeout
    described_class.refresh!(engine)
    expect(described_class.types(engine)).to eq(%w[location])

    travel(described_class::CACHE_TTL + 1.second) { expect(described_class.types(engine)).to eq([]) }
  end

  it 'reports 401/403 to the tracker with the engine name and without the key' do
    tracker = instance_double(ChatwootExceptionTracker, capture_exception: nil)
    allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)
    stub_request(:get, url).to_return(status: 401, body: 'no')

    with_modified_env(WAHA_API_KEY: 'segredo-do-motor') { described_class.refresh!(engine) }

    expect(ChatwootExceptionTracker).to have_received(:new) do |error|
      expect(error.message).to include(engine).and(include('401'))
      expect(error.message).not_to include('segredo-do-motor')
    end
    expect(tracker).to have_received(:capture_exception)
  end

  describe Waha::EngineCapabilitiesRefreshJob do
    it 'refreshes every listed engine, one failing not stopping the other' do
      stub_request(:get, url).to_timeout
      stub_request(:get, 'https://outro.example/api/server/version')
        .to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: { autonomia: { rich_native: %w[contact] } }.to_json)

      described_class.perform_now

      expect(Waha::EngineCapabilities.types('https://outro.example/')).to eq(%w[contact])
      expect(Waha::EngineCapabilities.types(engine)).to eq([])
    end

    it 'does nothing without the engine list' do
      allow(HTTParty).to receive(:get)

      with_modified_env(WAHA_RICH_NATIVE_ENGINES: '') { described_class.perform_now }

      expect(HTTParty).not_to have_received(:get)
    end

    it 'is a valid sidekiq-cron entry, every minute at second 25' do
      entry = YAML.load_file(Rails.root.join('config/schedule.yml'))['waha_engine_capabilities_refresh_job']
      job = Sidekiq::Cron::Job.new(name: 'waha_engine_capabilities_refresh_job', **entry.symbolize_keys)

      expect(job.valid?).to be(true)
      expect(entry).to include('class' => described_class.name, 'queue' => 'scheduled_jobs')
      expect(Fugit.parse_cron(entry['cron']).next_time(Time.utc(2026, 10, 16, 12, 0, 0)).to_t.utc).to eq(Time.utc(2026, 10, 16, 12, 0, 25))
    end
  end
end
