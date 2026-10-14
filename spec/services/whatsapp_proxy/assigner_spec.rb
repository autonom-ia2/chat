require 'rails_helper'

RSpec.describe WhatsappProxy::Assigner do
  let(:client) { instance_double(Webshare::Client, configured?: true) }
  let(:engine) { instance_double(Waha::Client, list_sessions: []) }
  let(:assigner) { described_class.new(client: client, engine: engine) }
  let(:rio) { webshare_proxy(id: 1, address: '10.0.0.1', city: 'Rio de Janeiro') }
  let(:sao_paulo) { webshare_proxy(id: 2, address: '10.0.0.2', city: 'São Paulo') }
  let(:sao_paolo) { webshare_proxy(id: 3, address: '10.0.0.3', city: 'Sao Paolo') }
  let(:us) { webshare_proxy(id: 4, address: '10.0.0.4', country: 'US', city: 'New York') }

  around { |example| with_modified_env(WHATSAPP_PROXY_ENABLED: 'true') { example.run } }

  before { Redis::Alfred.delete(described_class::BACKOFF_KEY) }

  def assign!(session, proxy, digest: nil)
    WhatsappProxy::Assignment.create!(session_name: session, webshare_proxy_id: proxy.id, proxy_address: proxy.address,
                                      proxy_port: proxy.port, assigned_at: 1.day.ago, credential_digest: digest)
  end

  it 'assigns a free Brazilian IP, São Paulo first, and records only address and port' do
    allow(client).to receive(:proxies).and_return([us, rio, sao_paulo])

    proxy = assigner.for('5511900000001')

    expect(proxy.server).to eq('10.0.0.2:6000')
    expect(proxy.to_session_config).to eq(server: '10.0.0.2:6000', username: 'user-2', password: 'senha-2')
    record = WhatsappProxy::Assignment.find_by!(session_name: '5511900000001')
    expect(record.attributes.values.map(&:to_s)).not_to include('senha-2', 'user-2')
  end

  it 'accepts the "Sao Paolo" spelling as São Paulo' do
    allow(client).to receive(:proxies).and_return([rio, sao_paolo])

    expect(assigner.for('5511900000001').address).to eq('10.0.0.3')
  end

  it 'keeps the IP already assigned while it is valid on the list' do
    assign!('5511900000001', rio)
    allow(client).to receive(:proxies).and_return([sao_paulo, rio])

    expect(assigner.for('5511900000001').address).to eq('10.0.0.1')
  end

  it 'never gives the same IP to two numbers' do
    assign!('5511900000001', sao_paulo)
    allow(client).to receive(:proxies).and_return([sao_paulo, rio])

    expect(assigner.for('5511900000002').address).to eq('10.0.0.1')
  end

  it 'reassigns when the assigned IP left the list or became invalid' do
    assign!('5511900000001', sao_paulo, digest: 'old')
    allow(client).to receive(:proxies).and_return([webshare_proxy(id: 2, address: '10.0.0.2', valid: false), rio])

    log = capture_log { expect(assigner.for('5511900000001').address).to eq('10.0.0.1') }

    record = WhatsappProxy::Assignment.find_by!(session_name: '5511900000001')
    expect(record.proxy_address).to eq('10.0.0.1')
    expect(record.credential_digest).to be_nil
    expect(log).to include('10.0.0.2:6000 saiu da lista')
  end

  it 'stays off, without calling Webshare, unless WHATSAPP_PROXY_ENABLED is "true"' do
    allow(client).to receive(:proxies)

    %w[false 1 TRUE].push(nil).each do |value|
      with_modified_env(WHATSAPP_PROXY_ENABLED: value) do
        expect(assigner).not_to be_enabled
        expect(assigner.for('5511900000001')).to be_nil
      end
    end
    expect(client).not_to have_received(:proxies)
  end

  it 'skips IPs the engine already uses, even without a record, keeping only the host' do
    allow(engine).to receive(:list_sessions).with(all: true).and_return(
      [{ 'name' => '5511900000009', 'config' => { 'proxy' => { 'server' => '10.0.0.2:6000', 'password' => 'manual-secret' } } },
       { 'name' => '5511900000008', 'config' => { 'proxy' => { 'server' => 'http://10.0.0.1:6000' } } },
       { 'name' => '5511900000007', 'config' => {} }]
    )
    third = webshare_proxy(id: 5, address: '10.0.0.5', city: 'Campinas')
    allow(client).to receive(:proxies).and_return([sao_paulo, rio, third])

    log = capture_log { expect(assigner.for('5511900000001').address).to eq('10.0.0.5') }

    expect(log).not_to include('manual-secret')
  end

  it 'ignores the proxy of the session itself in the engine' do
    allow(client).to receive(:proxies).and_return([sao_paulo])
    allow(engine).to receive(:list_sessions).and_return(
      [{ 'name' => '5511900000001', 'config' => { 'proxy' => { 'server' => '10.0.0.2:6000' } } }]
    )

    expect(assigner.for('5511900000001').address).to eq('10.0.0.2')
  end

  it 'assigns nothing when the engine cannot list its sessions' do
    allow(client).to receive(:proxies).and_return([sao_paulo])
    allow(engine).to receive(:list_sessions).and_raise(Waha::Client::Error, 'down')

    expect(assigner.for('5511900000001')).to be_nil
    expect(WhatsappProxy::Assignment.count).to eq(0)
  end

  it 'returns nil without the API key, and the session goes on without proxy' do
    allow(client).to receive(:configured?).and_return(false)
    allow(client).to receive(:proxies)

    log = capture_log { expect(assigner.for('5511900000001')).to be_nil }

    expect(client).not_to have_received(:proxies)
    expect(log).to include('WEBSHARE_API_KEY ausente')
  end

  it 'returns nil and warns when the pool has no free IP' do
    assign!('5511900000001', sao_paulo)
    allow(client).to receive(:proxies).and_return([sao_paulo, us])

    log = capture_log { expect(assigner.for('5511900000002')).to be_nil }

    expect(log).to include('sem IP livre')
    expect(WhatsappProxy::Assignment.count).to eq(1)
  end

  it 'returns nil when the API is down and pauses the frequent callers' do
    allow(client).to receive(:proxies).and_raise(Webshare::Client::Error, 'webshare_list_failed status=503')

    expect(assigner.for('5511900000001')).to be_nil
    expect(assigner.for('5511900000001', honor_backoff: true)).to be_nil
    expect(client).to have_received(:proxies).once
  end

  it 'leaves an external (hand-made, non Webshare) proxy alone' do
    WhatsappProxy::Assignment.create!(session_name: 'hybrid-5511900000001', proxy_address: '200.1.1.1', proxy_port: 3128,
                                      assigned_at: 1.day.ago)
    allow(client).to receive(:proxies).and_return([sao_paulo])

    expect(assigner.for('hybrid-5511900000001')).to be_nil
    expect(WhatsappProxy::Assignment.find_by!(session_name: 'hybrid-5511900000001').proxy_address).to eq('200.1.1.1')
  end

  it 'records the credential digest once applied and frees the IP on release' do
    allow(client).to receive(:proxies).and_return([sao_paulo])
    proxy = assigner.for('5511900000001')

    assigner.mark_applied!('5511900000001', proxy)
    expect(WhatsappProxy::Assignment.last.credential_digest).to eq(proxy.credential_digest)
    expect(proxy.credential_digest).not_to include('senha-2')

    assigner.release!('5511900000001')
    expect(WhatsappProxy::Assignment.count).to eq(0)
  end

  it 'never logs the proxy credential' do
    assign!('5511900000001', sao_paulo)
    allow(client).to receive(:proxies).and_return([webshare_proxy(id: 2, address: '10.0.0.2', valid: false), rio])

    log = capture_log do
      assigner.for('5511900000001')
      assigner.for('5511900000002')
    end

    expect(log).not_to include('senha-')
    expect(log).not_to include('user-')
    expect(rio.inspect).not_to include('senha-1')
    expect(rio.to_s).not_to include('user-1')
  end
end
