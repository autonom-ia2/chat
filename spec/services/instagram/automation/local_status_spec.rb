require 'rails_helper'

RSpec.describe Instagram::Automation::LocalStatus do
  subject(:status) { described_class.new.call }

  let(:namespace) { "automation-status-#{SecureRandom.hex(6)}" }
  let(:version) { SecureRandom.uuid }
  let(:pointer_key) { "#{Instagram::Testers::SessionStore::ROOT_KEY}:#{namespace}:pointer" }
  let(:payload_key) { "#{Instagram::Testers::SessionStore::ROOT_KEY}:#{namespace}:payload:#{version}" }
  let(:pointer) { { state: 'active', version: version, updated_at: Time.current.iso8601, captured_at: Time.current.iso8601 } }
  let(:metadata) do
    {
      'INSTAGRAM_META_DEVELOPER_APP_ID' => '10001', 'INSTAGRAM_META_BUSINESS_ID' => '10002',
      'INSTAGRAM_TESTER_APP_NAME' => 'Synthetic App', 'INSTAGRAM_TESTER_ADMIN_USER_ID' => '10003',
      'INSTAGRAM_TESTER_ROLES_DOC_ID' => '10004'
    }
  end
  let(:environment) do
    metadata.merge(
      'INSTAGRAM_TESTER_AUTOMATION_ENABLED' => 'true', 'INSTAGRAM_TESTER_SESSION_SOURCE' => 'managed',
      'INSTAGRAM_TESTER_SESSION_NAMESPACE' => namespace, 'INSTAGRAM_TESTER_PROXY_HOST' => '192.0.2.10',
      'INSTAGRAM_TESTER_PROXY_PORT' => '8080', 'INSTAGRAM_TESTER_PROXY_AUTH_MODE' => 'ip',
      'INSTAGRAM_TESTER_PROXY_IDENTITY' => '192.0.2.10:8080',
      'INSTAGRAM_TESTER_PROXY_USERNAME' => '', 'INSTAGRAM_TESTER_PROXY_PASSWORD' => '',
      'INSTAGRAM_TESTER_OPERATOR_BROWSER_URL' => 'https://gateway.invalid/hub2you/',
      'INSTAGRAM_TESTER_RUNTIME_STACK' => 'hub2you', 'FRONTEND_URL' => 'https://hub.invalid',
      'INSTAGRAM_TESTER_OPERATOR_BROWSER_SIGNING_KEY' => 'a' * 64,
      'INSTAGRAM_TESTER_COORDINATION_REDIS_URL' => 'rediss://:synthetic-password@redis.invalid:6379/0',
      'INSTAGRAM_TESTER_COORDINATION_EPOCH' => 'synthetic-status-epoch', 'INSTAGRAM_TESTER_COORDINATION_REDIS_CA_FILE' => ''
    )
  end

  around { |example| with_modified_env(environment) { example.run } }

  after do
    Redis::Alfred.delete(pointer_key)
    Redis::Alfred.delete(payload_key)
  end

  it 'returns only local sanitized facts and leaves both remote connectivities unknown' do
    create(:installation_config, name: 'DISABLE_META_INBOX_CREATION', value: 'true')
    expect(Instagram::Testers::Client).not_to receive(:new)
    expect(Instagram::Testers::CoordinationRedis).not_to receive(:with)
    expect(Redis::SecureStorage).not_to receive(:get)
    expect(status.fetch(:checked_at)).to be_a(Time)
    expect(status.fetch(:checked_at)).to be_between(5.seconds.ago, Time.current)
    expect(status.except(:checked_at)).to eq(
      global_gate: true, config_complete: true, managed_session: true,
      session: { state: 'missing', present: false, ttl: nil }, proxy: { configured: true, valid: true },
      coordination: { configured: true }, meta_creation_disabled: true, operator_browser_configured: true,
      manager_connectivity: 'unknown', meta_connectivity: 'unknown', manager: nil, control: nil, operator_required: false, control_available: false
    )
  end

  it 'reports browser configuration without exposing its URL or signing key' do
    expect(status[:operator_browser_configured]).to be(true)
    expect(status.to_json).not_to include('gateway.invalid', 'a' * 64)
    with_modified_env('INSTAGRAM_TESTER_OPERATOR_BROWSER_URL' => 'http://gateway.invalid/hub2you/') do
      expect(described_class.new.call[:operator_browser_configured]).to be(false)
    end
    with_modified_env('INSTAGRAM_TESTER_SESSION_SOURCE' => 'env') do
      expect(described_class.new.call[:operator_browser_configured]).to be(false)
    end
  end

  it 'checks payload existence and TTL without reading or returning its contents or the pointer version' do
    Redis::Alfred.set(pointer_key, pointer.to_json, ex: 120)
    Redis::Alfred.set(payload_key, 'synthetic-private-payload', ex: 90)
    allow(Redis::Alfred).to receive(:get).and_call_original
    expect(Redis::Alfred).not_to receive(:get).with(payload_key)
    expect(Redis::SecureStorage).not_to receive(:get)
    expect(status[:session]).to include(state: 'active', present: true)
    expect(status[:session][:ttl]).to be_between(1, 90)
    expect(status.to_json).not_to include(version, 'synthetic-private-payload', 'synthetic-password', '192.0.2.10')
  end

  it 'reports an active pointer with no payload as missing' do
    Redis::Alfred.set(pointer_key, pointer.to_json, ex: 120)
    expect(status[:session]).to eq(state: 'missing', present: false, ttl: nil)
  end

  it 'reports invalidation without exposing its code or touching the payload' do
    pointer.merge!(state: 'invalidated', code: 'http_401', invalidated_at: Time.current.iso8601)
    Redis::Alfred.set(pointer_key, pointer.to_json, ex: 120)
    allow(Redis::Alfred).to receive(:get).and_call_original
    expect(Redis::Alfred).not_to receive(:get).with(payload_key)
    expect(status[:session]).to include(state: 'invalidated', present: false)
    expect(status.to_json).not_to include('http_401', version)
  end

  it 'reports invalid pointers without echoing arbitrary content' do
    Redis::Alfred.set(pointer_key, { state: 'synthetic-secret' }.to_json, ex: 120)
    expect(status[:session]).to eq(state: 'invalid', present: false, ttl: nil)
  end

  it 'reports local Redis failure as unavailable without error details' do
    allow(Redis::Alfred).to receive(:get).with(pointer_key).and_raise(Redis::CannotConnectError, 'synthetic-secret')
    expect(status[:session]).to eq(state: 'unavailable', present: false, ttl: nil)
  end

  it 'does not read legacy ENV session secrets' do
    with_modified_env('INSTAGRAM_TESTER_SESSION_SOURCE' => 'env', 'INSTAGRAM_TESTER_SESSION_JSON' => 'synthetic-secret') do
      expect(ENV).not_to receive(:fetch).with('INSTAGRAM_TESTER_SESSION_JSON', anything)
      expect(status[:session]).to eq(state: 'unmanaged', present: nil, ttl: nil)
    end
  end

  it 'uses saved metadata for completeness, including explicit empty overrides' do
    create(:installation_config, name: 'INSTAGRAM_META_DEVELOPER_APP_ID', value: '')
    expect(status[:config_complete]).to be(false)
  end

  it 'reports an unconfigured or incomplete proxy without raising a runtime parsing error' do
    with_modified_env('INSTAGRAM_TESTER_PROXY_HOST' => '', 'INSTAGRAM_TESTER_PROXY_PORT' => '',
                      'INSTAGRAM_TESTER_PROXY_AUTH_MODE' => '', 'INSTAGRAM_TESTER_PROXY_IDENTITY' => nil) do
      expect(status[:proxy]).to eq(configured: false, valid: false)
    end
    with_modified_env('INSTAGRAM_TESTER_PROXY_HOST' => '') do
      expect(described_class.new.call[:proxy]).to eq(configured: true, valid: false)
    end
  end

  it 'reports global gate and invalid local configuration independently' do
    with_modified_env('INSTAGRAM_TESTER_AUTOMATION_ENABLED' => 'false', 'INSTAGRAM_TESTER_PROXY_PORT' => 'invalid',
                      'INSTAGRAM_TESTER_COORDINATION_REDIS_URL' => '') do
      expect(status).to include(global_gate: false, proxy: { configured: true, valid: false }, coordination: { configured: false })
    end
  end
end
