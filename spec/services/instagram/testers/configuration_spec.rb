require 'rails_helper'

RSpec.describe Instagram::Testers::Configuration do
  subject(:configuration) { described_class.new(account_id: account.id) }

  let(:account) { create(:account) }

  let(:session) do
    { cookie: 'synthetic=fixture', fb_dtsg: 'synthetic-dtsg', lsd: 'synthetic-lsd', jazoest: '1234',
      user_id: '12345', user_agent: 'Synthetic Test Client', extra_form: { __req: '1' } }
  end
  let(:settings) do
    { 'INSTAGRAM_TESTER_AUTOMATION_ENABLED' => 'true', 'INSTAGRAM_TESTER_ALLOWED_ACCOUNT_IDS' => account.id.to_s,
      'INSTAGRAM_META_DEVELOPER_APP_ID' => '10001', 'INSTAGRAM_META_BUSINESS_ID' => '10002',
      'INSTAGRAM_TESTER_ROLES_DOC_ID' => '10003', 'INSTAGRAM_TESTER_APP_NAME' => 'Synthetic app',
      'INSTAGRAM_TESTER_SESSION_JSON' => session.to_json }
  end

  before { account.enable_features!(:channel_instagram, :instagram_assisted_onboarding) }

  around { |example| with_modified_env(settings) { example.run } }

  it 'exposes only safe configuration and requires all configured fields' do
    expect(configuration.public_configuration).to eq(enabled: true, available: true, app_name: 'Synthetic app',
                                                     acceptance_url: described_class::ACCEPTANCE_URL)
    with_modified_env('INSTAGRAM_TESTER_ROLES_DOC_ID' => '') do
      expect(described_class.new(account_id: account.id).available?).to be false
      expect(configuration.available?).to be true
      expect(configuration.doc_id).to eq('10003')
    end
  end

  it 'allows an empty legacy allowlist while requiring the account feature and global switch' do
    with_modified_env('INSTAGRAM_TESTER_ALLOWED_ACCOUNT_IDS' => '') { expect(configuration.enabled?).to be true }
    with_modified_env('INSTAGRAM_TESTER_ALLOWED_ACCOUNT_IDS' => nil) { expect(configuration.enabled?).to be true }
    with_modified_env('INSTAGRAM_TESTER_AUTOMATION_ENABLED' => nil) { expect(configuration.enabled?).to be false }
    with_modified_env('INSTAGRAM_TESTER_AUTOMATION_ENABLED' => 'yes') { expect(configuration.enabled?).to be false }
    account.disable_features!(:instagram_assisted_onboarding)
    expect(configuration.enabled?).to be false
  end

  it 'keeps a present allowlist as an additional restriction and fails closed when malformed' do
    ["#{account.id},", "#{account.id},all", (account.id + 1).to_s].each do |value|
      with_modified_env('INSTAGRAM_TESTER_ALLOWED_ACCOUNT_IDS' => value) { expect(configuration.enabled?).to be false }
    end
    with_modified_env('INSTAGRAM_TESTER_ALLOWED_ACCOUNT_IDS' => " #{account.id}, #{account.id + 1} ") do
      expect(configuration.enabled?).to be true
    end
  end

  it 'keeps the Instagram channel entitlement required even with assisted onboarding ON' do
    account.disable_features!('channel_instagram')
    expect(Instagram::Testers::SessionStore).not_to receive(:new)
    expect(configuration.public_configuration).to eq(enabled: false, available: false, app_name: nil,
                                                     acceptance_url: described_class::ACCEPTANCE_URL)
  end

  it 'does not read tester infrastructure when the account feature is off' do
    account.disable_features!(:instagram_assisted_onboarding)
    expect(Instagram::Testers::SessionStore).not_to receive(:new)
    expect(Instagram::Testers::Proxy).not_to receive(:new)
    expect(configuration.public_configuration).to eq(enabled: false, available: false, app_name: nil,
                                                     acceptance_url: described_class::ACCEPTANCE_URL)
  end

  it 'isolates toggles and preserves explicit OFF after reload' do
    other = create(:account)
    other.enable_features!(:channel_instagram, :instagram_assisted_onboarding)
    account.disable_features!(:instagram_assisted_onboarding)
    with_modified_env('INSTAGRAM_TESTER_ALLOWED_ACCOUNT_IDS' => '') do
      expect(configuration.enabled?).to be false
      expect(described_class.new(account_id: other.id).enabled?).to be true
      expect(account.reload.feature_enabled?('instagram_assisted_onboarding')).to be false
    end
  end

  it 'rejects arbitrary session and instrumentation fields' do
    [session.merge(endpoint: 'https://example.com'), session.merge(extra_form: { role: 'admin' }), session.except(:lsd),
     session.merge(cookie: "synthetic\nheader")].each do |value|
      with_modified_env('INSTAGRAM_TESTER_SESSION_JSON' => value.to_json) do
        expect(described_class.new(account_id: account.id).available?).to be false
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
                      'INSTAGRAM_TESTER_PROXY_IDENTITY' => '192.0.2.10:8080',
                      'INSTAGRAM_TESTER_PROXY_AUTH_MODE' => 'ip',
                      'INSTAGRAM_TESTER_PROXY_USERNAME' => nil, 'INSTAGRAM_TESTER_PROXY_PASSWORD' => nil,
                      'INSTAGRAM_TESTER_COORDINATION_REDIS_URL' => nil) do
      managed_store = instance_double(Instagram::Testers::SessionStore,
                                      current_snapshot: { session: session, version: SecureRandom.uuid }.freeze)
      allow(Instagram::Testers::SessionStore).to receive(:new).with(configuration: configuration).and_return(managed_store)

      expect(configuration.available?).to be false
      with_modified_env('INSTAGRAM_TESTER_COORDINATION_REDIS_URL' => 'rediss://:synthetic@coordination.invalid:6379/0',
                        'INSTAGRAM_TESTER_COORDINATION_EPOCH' => 'synthetic-configuration-epoch',
                        'INSTAGRAM_TESTER_COORDINATION_REDIS_CA_FILE' => '') do
        expect(configuration.available?).to be true
      end
    end
  end
end
