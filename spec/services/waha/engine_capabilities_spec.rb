require 'rails_helper'

# chat#1709 (fase 2): o que o motor com o conector customizado declara em /api/server/version.
RSpec.describe Waha::EngineCapabilities do
  let(:url) { 'https://waha.example/api/server/version' }

  around { |example| with_modified_env(WAHA_RICH_NATIVE_ENGINES: ' https://waha.example , https://outro.example/ ') { example.run } }

  def version(autonomia)
    stub_request(:get, url).to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                                      body: { version: '2026.9.2', engine: 'GOWS', autonomia: autonomia }.compact.to_json)
  end

  it 'lists the engines with the trailing slash and matches the webhook by prefix, slash included' do
    expect(described_class.engines).to eq(%w[https://waha.example/ https://outro.example/])
    expect(described_class.engine_for('https://waha.example/webhooks/chatwoot/1')).to eq('https://waha.example/')
    expect(described_class.engine_for('https://waha.example.evil.com/webhooks')).to be_nil
    expect(with_modified_env(WAHA_RICH_NATIVE_ENGINES: '') { described_class.engine_for('https://waha.example/x') }).to be_nil
  end

  it 'reads the declared types; options only with list_reply' do
    version({ patch: 'c2y-rich-1', rich_native: %w[options location contact carousel], list_reply: true })
    expect(described_class.types('https://waha.example/')).to eq(%w[options location contact])

    version({ patch: 'c2y-rich-1', rich_native: %w[options location], list_reply: false })
    expect(described_class.types('https://waha.example/')).to eq(%w[location])
  end

  it 'is empty when the engine has no patch, errors or does not answer' do
    version(nil)
    expect(described_class.types('https://waha.example/')).to eq([])

    stub_request(:get, url).to_return(status: 500, body: 'boom')
    expect(described_class.types('https://waha.example/')).to eq([])

    stub_request(:get, url).to_timeout
    expect(described_class.types('https://waha.example/')).to eq([])
    expect(described_class.types(nil)).to eq([])
  end
end
