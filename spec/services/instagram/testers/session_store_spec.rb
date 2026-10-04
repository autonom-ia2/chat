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
    revoked_version = store.current_version
    expect(revoked_version).not_to eq(version)
    expect(store.current_snapshot).to eq(session: nil, version: revoked_version)
    expect(store.invalidate(version: version, code: 'operator_required')).to be(false)

    pointer = JSON.parse(Redis::Alfred.get(pointer_key))
    before_invalidation = Time.iso8601(pointer.fetch('invalidated_at')) - 0.000001
    expect do
      publish(expected_version: revoked_version, captured_at: before_invalidation)
    end.to(raise_error { |error| expect(error.code).to eq('session_update_rejected') })

    replacement = publish(expected_version: revoked_version, candidate: session.merge('fb_dtsg' => 'replacement'))
    expect(store.current_snapshot).to include(session: session.merge('fb_dtsg' => 'replacement'), version: replacement)
  end

  it 'allows fresh reauthorization after the invalidated encrypted payload expires' do
    version = publish(captured_at: 2.seconds.ago)
    store.invalidate(version: version, code: 'http_401')
    allow(Redis::SecureStorage).to receive(:get).and_return(nil)

    replacement = publish(expected_version: store.current_version, captured_at: Time.current)

    expect(store.current_version).to eq(replacement)
  end

  it 'fences a prepared publication revoked before CAS even with four minutes of publisher clock skew' do
    freeze_time do
      version = publish(captured_at: 1.minute.ago)
      candidate_key = nil
      revoked_version = nil
      allow(Redis::SecureStorage).to receive(:set).and_wrap_original do |original, key, *arguments|
        original.call(key, *arguments)
        candidate_key = key
        travel 1.second
        expect(store.invalidate(version: version, code: 'operator_required')).to be(true)
        revoked_version = store.current_version
        expect(store.current_snapshot).to eq(session: nil, version: revoked_version)
      end

      expect { publish(expected_version: version, captured_at: 240.seconds.from_now) }
        .to(raise_error { |error| expect(error.code).to eq('session_update_rejected') })

      expect(revoked_version).not_to eq(version)
      expect(store.current_snapshot).to eq(session: nil, version: revoked_version)
      expect(Redis::Alfred.get(candidate_key)).to be_nil
    end
  end

  it 'rejects stale publishers and recovers only against the newly read revoked revision' do
    freeze_time do
      version = publish(captured_at: 1.minute.ago)
      store.invalidate(version: version, code: 'http_403')
      revoked_version = store.current_version

      [nil, version].each do |expected_version|
        expect { publish(expected_version: expected_version, captured_at: 240.seconds.from_now) }
          .to(raise_error { |error| expect(error.code).to eq('session_update_rejected') })
      end
      expect(store.current_snapshot).to eq(session: nil, version: revoked_version)

      travel 1.second
      replacement = publish(expected_version: revoked_version)
      expect(store.current_snapshot).to eq(session: session, version: replacement)
      expect(store.invalidate(version: revoked_version, code: 'http_401')).to be(false)
      expect(store.current_version).to eq(replacement)
    end
  end

  it 'does not invalidate a replacement published after the invalidator read the old pointer' do
    freeze_time do
      version = publish(captured_at: 1.minute.ago)
      replacement = nil
      pending = true
      allow(Redis::Alfred).to receive(:with).and_wrap_original do |original, &block|
        if pending
          pending = false
          travel 1.second
          replacement = publish(expected_version: version)
        end
        original.call(&block)
      end

      expect(store.invalidate(version: version, code: 'http_401')).to be(false)
      expect(store.current_snapshot).to eq(session: session, version: replacement)
    end
  end

  it 'rotates a legacy invalidated pointer without changing its schema or needing the old payload' do
    version = publish(captured_at: 1.minute.ago)
    pointer = JSON.parse(Redis::Alfred.get(pointer_key))
    invalidated_at = 1.second.ago.utc.iso8601(6)
    legacy = pointer.merge('state' => 'invalidated', 'code' => 'http_401',
                           'updated_at' => invalidated_at, 'invalidated_at' => invalidated_at)
    Redis::Alfred.set(pointer_key, JSON.generate(legacy), ex: described_class::POINTER_TTL)
    Redis::Alfred.delete(store.send(:payload_key, version))

    expect(store.invalidate(version: version, code: 'http_401')).to be(true)
    revoked_version = store.current_version
    expect(revoked_version).not_to eq(version)
    expect(JSON.parse(Redis::Alfred.get(pointer_key)).keys).to match_array(legacy.keys)
    expect { publish(expected_version: version, captured_at: 240.seconds.from_now) }
      .to(raise_error { |error| expect(error.code).to eq('session_update_rejected') })

    replacement = publish(expected_version: revoked_version)
    expect(store.current_snapshot).to eq(session: session, version: replacement)
  end

  it 'keeps the revision fence when ciphertext is corrupt and permits a newly captured replacement' do
    version = publish(captured_at: 1.minute.ago)
    Redis::Alfred.set(store.send(:payload_key, version), 'corrupt-ciphertext', ex: described_class::MAX_SESSION_TTL.to_i)

    expect(store.current_snapshot).to eq(session: nil, version: version)
    expect(store.invalidate(version: version, code: 'http_401')).to be(true)
    revoked_version = store.current_version
    replacement = publish(expected_version: revoked_version)

    expect(store.current_snapshot).to eq(session: session, version: replacement)
  end

  it 'expires a future-skewed capture and its pointer at six server hours' do
    freeze_time do
      version = publish(captured_at: 240.seconds.from_now)
      key = store.send(:payload_key, version)
      payload = JSON.parse(Redis::SecureStorage.get(key))
      expect(Time.iso8601(payload.fetch('expires_at'))).to eq(6.hours.from_now)
      expect(Redis::Alfred.ttl(key)).to eq(described_class::MAX_SESSION_TTL.to_i)
      expect(Redis::Alfred.ttl(pointer_key)).to eq(described_class::MAX_SESSION_TTL.to_i)

      # Alfred uses MockRedis in test, so travel advances both freshness checks and key expiry.
      travel 6.hours
      expect(store.current_snapshot).to eq(session: nil, version: nil)
      expect([Redis::Alfred.get(key), Redis::Alfred.get(pointer_key)]).to eq([nil, nil])
      replacement = publish(expected_version: store.current_version)
      expect(store.current_snapshot).to eq(session: session, version: replacement)
    end
  end

  it 'keeps the session and revision available one second before the six-hour TTL' do
    freeze_time do
      version = publish(captured_at: 240.seconds.from_now)

      travel(6.hours - 1.second)
      expect(Redis::Alfred.ttl(store.send(:payload_key, version))).to eq(1)
      expect(Redis::Alfred.ttl(pointer_key)).to eq(1)
      expect(store.current_snapshot).to eq(session: session, version: version)
      expect(store.current_version).to eq(version)
      expect { publish(expected_version: nil) }
        .to(raise_error { |error| expect(error.code).to eq('session_update_rejected') })
      expect(store.current_snapshot).to eq(session: session, version: version)
    end
  end

  it 'requires a fresh null publication after TTL and rejects an expired revision or six-hour-old capture' do
    freeze_time do
      version = publish(captured_at: 240.seconds.from_now)

      travel(6.hours + 1.second)
      expect(store.current_snapshot).to eq(session: nil, version: nil)
      expect(store.current_version).to be_nil
      expect { publish(expected_version: version) }
        .to(raise_error { |error| expect(error.code).to eq('session_update_rejected') })
      expect { publish(expected_version: nil, captured_at: 6.hours.ago) }
        .to(raise_error { |error| expect(error.code).to eq('session_update_rejected') })

      replacement = publish(expected_version: store.current_version)
      expect(store.current_snapshot).to eq(session: session, version: replacement)
    end
  end

  it 'rejects a corrupt pointer instead of letting an initial null publisher overwrite it' do
    Redis::Alfred.set(pointer_key, 'corrupt-json', ex: described_class::POINTER_TTL)

    expect(store.current_snapshot).to eq(session: nil, version: nil)
    expect { store.current_version }
      .to(raise_error { |error| expect(error.code).to eq('session_update_rejected') })
    expect { publish(expected_version: nil) }
      .to(raise_error { |error| expect(error.code).to eq('session_update_rejected') })
    expect(Redis::Alfred.get(pointer_key)).to eq('corrupt-json')
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
