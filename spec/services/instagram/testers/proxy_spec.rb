require 'rails_helper'

RSpec.describe Instagram::Testers::Proxy do
  let(:settings) do
    { 'INSTAGRAM_TESTER_PROXY_HOST' => '127.0.0.1', 'INSTAGRAM_TESTER_PROXY_PORT' => '9100',
      'INSTAGRAM_TESTER_PROXY_AUTH_MODE' => 'ip',
      'INSTAGRAM_TESTER_PROXY_USERNAME' => nil, 'INSTAGRAM_TESTER_PROXY_PASSWORD' => nil }
  end

  around { |example| with_modified_env(settings) { example.run } }

  it 'configures only an explicit proxy and disables transport retries' do
    expect(described_class.new.transport_options).to eq(
      http_proxyaddr: '127.0.0.1',
      http_proxyport: 9100,
      http_proxyuser: nil,
      http_proxypass: nil,
      max_retries: 0
    )
  end

  ['', '0', '65536', '9100x'].each do |port|
    it "rejects an invalid proxy port #{port.inspect} before network traffic" do
      with_modified_env('INSTAGRAM_TESTER_PROXY_PORT' => port) do
        expect { described_class.new.transport_options }.to(raise_error { |error| expect(error.code).to eq('proxy_unavailable') })
      end
    end
  end

  it 'rejects a URL, credentials in the host or control characters' do
    ['http://127.0.0.1', 'user@127.0.0.1', 'p.webshare.io', '999.999.999.999', "127.0.0.1\n"].each do |host|
      with_modified_env('INSTAGRAM_TESTER_PROXY_HOST' => host) { expect(described_class.new.valid?).to be false }
    end
  end

  it 'rejects Basic, absent auth mode and credentials instead of sending them in cleartext' do
    [nil, '', 'basic'].each do |mode|
      with_modified_env('INSTAGRAM_TESTER_PROXY_AUTH_MODE' => mode) { expect(described_class.new.valid?).to be false }
    end
    %w[INSTAGRAM_TESTER_PROXY_USERNAME INSTAGRAM_TESTER_PROXY_PASSWORD].each do |key|
      with_modified_env(key => 'synthetic-secret') do
        expect { described_class.new.transport_options }.to raise_error do |error|
          expect(error.code).to eq('proxy_unavailable')
        end
      end
    end
  end

  it 'binds the session to a stable endpoint without publishing credentials' do
    original = described_class.new.fingerprint
    expect(original.length).to eq(64)
    with_modified_env('INSTAGRAM_TESTER_PROXY_HOST' => '127.0.0.2') { expect(described_class.new.fingerprint).not_to eq(original) }
    expect(original).to eq(Digest::SHA256.hexdigest('127.0.0.1:9100:ip'))
  end
end
