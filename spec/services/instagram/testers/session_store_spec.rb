require 'rails_helper'

RSpec.describe Instagram::Testers::SessionStore do
  subject(:store) { described_class.new(configuration: configuration) }

  let(:namespace) { "instagram-session-store-spec-#{SecureRandom.hex(6)}" }
  let(:proxy_fingerprint) { 'a' * 64 }
  let(:configuration) do
    instance_double(
      Instagram::Testers::Configuration,
      app_id: '10001',
      business_id: '10002',
      admin_user_id: '12345',
      proxy_fingerprint: proxy_fingerprint
    )
  end
  let(:session) do
    {
      'cookie' => 'c_user=12345; xs=synthetic-session',
      'fb_dtsg' => 'synthetic-dtsg',
      'lsd' => 'synthetic-lsd',
      'jazoest' => '1234',
      'user_id' => '12345',
      'user_agent' => 'Synthetic Browser',
      'extra_form' => { '__req' => '1' }
    }
  end
  let(:encryption_env) do
    {
      'ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY' => 'primary-key',
      'ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY' => 'deterministic-key',
      'ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT' => 'key-derivation-salt',
      'INSTAGRAM_TESTER_SESSION_NAMESPACE' => namespace
    }
  end
  let(:pointer_key) { "#{described_class::ROOT_KEY}:#{namespace}:pointer" }
  let(:versions) { [] }

  around do |example|
    with_modified_env(encryption_env) { example.run }
  end

  after do
    Redis::Alfred.delete(pointer_key)
    versions.each { |version| Redis::Alfred.delete(store.send(:payload_key, version)) }
  end

  def publish(expected_version: nil, candidate: session, captured_at: Time.current, **metadata)
    version = store.publish(
      session: candidate,
      expected_version: expected_version,
      captured_at: captured_at,
      app_id: metadata.fetch(:app_id, '10001'),
      business_id: metadata.fetch(:business_id, '10002'),
      proxy_fingerprint: metadata.fetch(:proxy_fingerprint, proxy_fingerprint)
    )
    versions << version
    version
  end

  it 'publishes encrypted payloads and reads a current immutable snapshot' do
    version = publish

    expect(store.current_version).to eq(version)
    expect(store.current_snapshot).to eq(session: session, version: version)
    expect(Redis::Alfred.get(store.send(:payload_key, version))).not_to include('c_user=12345')
  end

  it 'keeps the previous pointer when a stale publisher loses the CAS' do
    first = publish

    expect do
      publish(expected_version: nil, candidate: session.merge('fb_dtsg' => 'stale'))
    end.to(raise_error { |error| expect(error.code).to eq('session_update_rejected') })

    expect(store.current_version).to eq(first)
    expect(store.current_snapshot).to include(session: session, version: first)
  end

  it 'preserves the active session when the candidate is invalid or metadata differs' do
    first = publish

    [
      session.merge('cookie' => 'c_user=99999; xs=synthetic-session'),
      session.merge('extra_form' => { 'role' => 'admin' })
    ].each do |candidate|
      expect { publish(expected_version: first, candidate: candidate) }
        .to(raise_error { |error| expect(error.code).to eq('session_update_rejected') })
    end
    expect { publish(expected_version: first, business_id: '10003') }
      .to(raise_error { |error| expect(error.code).to eq('session_update_rejected') })

    expect(store.current_snapshot).to include(session: session, version: first)
  end

  it 'enforces a server-bounded six-hour capture window' do
    expect { publish(captured_at: 7.hours.ago) }
      .to(raise_error { |error| expect(error.code).to eq('session_update_rejected') })
    expect { publish(captured_at: 6.minutes.from_now) }
      .to(raise_error { |error| expect(error.code).to eq('session_update_rejected') })
  end

  it 'does not reactivate an invalidated session without an explicit publish' do
    version = publish(captured_at: 2.seconds.ago)

    expect(store.invalidate(version: version, code: 'http_401')).to be(true)
    expect(store.current_snapshot).to eq(session: nil, version: version)
    expect(store.current_version).to eq(version)
    expect(store.invalidate(version: version, code: 'operator_required')).to be(false)

    pointer = JSON.parse(Redis::Alfred.get(pointer_key))
    before_invalidation = Time.iso8601(pointer.fetch('invalidated_at')) - 0.000001
    expect do
      publish(expected_version: version, captured_at: before_invalidation)
    end.to(raise_error { |error| expect(error.code).to eq('session_update_rejected') })

    replacement = publish(expected_version: version, candidate: session.merge('fb_dtsg' => 'replacement'))
    expect(store.current_snapshot).to include(session: session.merge('fb_dtsg' => 'replacement'), version: replacement)
  end

  it 'allows fresh reauthorization after the invalidated encrypted payload expires' do
    version = publish(captured_at: 2.seconds.ago)
    store.invalidate(version: version, code: 'http_401')
    allow(Redis::SecureStorage).to receive(:get).and_return(nil)

    replacement = publish(expected_version: version, captured_at: Time.current)

    expect(store.current_version).to eq(replacement)
  end

  it 'rejects invalid namespace and encryption/storage failures before changing the pointer' do
    with_modified_env('INSTAGRAM_TESTER_SESSION_NAMESPACE' => '../unsafe') do
      expect { described_class.new(configuration: configuration) }
        .to(raise_error { |error| expect(error.code).to eq('session_update_rejected') })
    end

    allow(Redis::SecureStorage).to receive(:set).and_raise(Redis::SecureStorage::EncryptionNotConfigured)
    expect { publish }.to(raise_error { |error| expect(error.code).to eq('meta_unavailable') })
    expect(store.current_version).to be_nil
  end

  it 'rejects an invalidation for a stale version without changing the pointer' do
    version = publish
    stale = SecureRandom.uuid

    expect(store.invalidate(version: stale, code: 'http_403')).to be(false)
    expect(store.current_version).to eq(version)
  end

  it 'rejects unknown publication metadata before writing a payload' do
    expect do
      store.publish(
        session: session,
        expected_version: nil,
        captured_at: Time.current,
        app_id: '10001',
        business_id: '10002',
        proxy_fingerprint: proxy_fingerprint,
        tester_installation: 'unexpected'
      )
    end.to(raise_error { |error| expect(error.code).to eq('session_update_rejected') })

    expect(store.current_version).to be_nil
  end
end
