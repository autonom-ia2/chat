require 'rails_helper'

RSpec.describe Instagram::Testers::Configuration do
  subject(:configuration) { described_class.new(account_id: 16) }

  let(:session) do
    { cookie: 'synthetic=fixture', fb_dtsg: 'synthetic-dtsg', lsd: 'synthetic-lsd', jazoest: '1234',
      user_id: '12345', user_agent: 'Synthetic Test Client', extra_form: { __req: '1' } }
  end
  let(:settings) do
    { 'INSTAGRAM_TESTER_AUTOMATION_ENABLED' => 'true', 'INSTAGRAM_TESTER_ALLOWED_ACCOUNT_IDS' => '16, 17',
      'INSTAGRAM_META_DEVELOPER_APP_ID' => '10001', 'INSTAGRAM_META_BUSINESS_ID' => '10002',
      'INSTAGRAM_TESTER_ROLES_DOC_ID' => '10003', 'INSTAGRAM_TESTER_APP_NAME' => 'Synthetic app',
      'INSTAGRAM_TESTER_SESSION_JSON' => session.to_json }
  end

  around { |example| with_modified_env(settings) { example.run } }

  it 'exposes only safe configuration and requires all configured fields' do
    expect(configuration.public_configuration).to eq(enabled: true, available: true, app_name: 'Synthetic app',
                                                     acceptance_url: described_class::ACCEPTANCE_URL)
    with_modified_env('INSTAGRAM_TESTER_ROLES_DOC_ID' => '') do
      expect(configuration.available?).to be false
    end
  end

  it 'defaults off without an allowlist or with a malformed allowlist' do
    ['', '16,', '16,all'].each do |value|
      with_modified_env('INSTAGRAM_TESTER_ALLOWED_ACCOUNT_IDS' => value) { expect(configuration.enabled?).to be false }
    end
    with_modified_env('INSTAGRAM_TESTER_AUTOMATION_ENABLED' => nil) { expect(configuration.enabled?).to be false }
  end

  it 'requires explicit true and an allowed account' do
    with_modified_env('INSTAGRAM_TESTER_AUTOMATION_ENABLED' => 'yes') { expect(configuration.enabled?).to be false }
    expect(described_class.new(account_id: 18).enabled?).to be false
  end

  it 'rejects arbitrary session and instrumentation fields' do
    [session.merge(endpoint: 'https://example.com'), session.merge(extra_form: { role: 'admin' }), session.except(:lsd),
     session.merge(cookie: "synthetic\nheader")].each do |value|
      with_modified_env('INSTAGRAM_TESTER_SESSION_JSON' => value.to_json) do
        expect(described_class.new(account_id: 16).available?).to be false
      end
    end
  end

  it 'fails closed on invalid session JSON' do
    with_modified_env('INSTAGRAM_TESTER_SESSION_JSON' => 'synthetic invalid JSON') do
      expect(configuration.available?).to be false
    end
  end

  it 'reads a managed snapshot on every access without falling back to the environment session' do
    snapshot = { session: { 'user_id' => '12345' }, version: SecureRandom.uuid }.freeze
    managed_store = instance_double(Instagram::Testers::SessionStore, current_snapshot: snapshot)

    with_modified_env('INSTAGRAM_TESTER_SESSION_SOURCE' => 'managed',
                      'INSTAGRAM_TESTER_SESSION_NAMESPACE' => 'configuration-spec',
                      'INSTAGRAM_TESTER_ADMIN_USER_ID' => '12345') do
      allow(Instagram::Testers::SessionStore).to receive(:new).with(configuration: configuration).and_return(managed_store)

      expect(configuration.session_snapshot).to equal(snapshot)
      with_modified_env('INSTAGRAM_TESTER_SESSION_JSON' => '{"user_id":"attacker"}') do
        expect(configuration.session_snapshot).to equal(snapshot)
      end
    end
  end

  it 'preserves the Meta incident guardrail' do
    allow(GlobalConfig).to receive(:get_value).with('DISABLE_META_INBOX_CREATION').and_return(true)
    expect { configuration.ensure_available! }.to raise_error do |error|
      expect(error.code).to eq('forbidden')
    end
  end

  it 'requires managed sessions and explicit TLS invitation coordination in production' do
    allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))
    expect(configuration.available?).to be false

    with_modified_env('INSTAGRAM_TESTER_SESSION_SOURCE' => 'managed', 'INSTAGRAM_TESTER_ADMIN_USER_ID' => '12345',
                      'INSTAGRAM_TESTER_PROXY_HOST' => '127.0.0.1', 'INSTAGRAM_TESTER_PROXY_PORT' => '9100',
                      'INSTAGRAM_TESTER_PROXY_AUTH_MODE' => 'ip',
                      'INSTAGRAM_TESTER_PROXY_USERNAME' => nil, 'INSTAGRAM_TESTER_PROXY_PASSWORD' => nil,
                      'INSTAGRAM_TESTER_COORDINATION_REDIS_URL' => nil) do
      managed_store = instance_double(Instagram::Testers::SessionStore,
                                      current_snapshot: { session: session, version: SecureRandom.uuid }.freeze)
      allow(Instagram::Testers::SessionStore).to receive(:new).with(configuration: configuration).and_return(managed_store)

      expect(configuration.available?).to be false
      with_modified_env('INSTAGRAM_TESTER_COORDINATION_REDIS_URL' => 'rediss://:synthetic@coordination.invalid:6379/0') do
        expect(configuration.available?).to be true
      end
    end
  end
end
