require 'uri'
require 'timeout'
# Fail before Rails boot or any connection; never inherit ambient service endpoints.
if ENV.key?('TEST_REDIS_URL')
  uri = URI.parse(ENV.fetch('TEST_REDIS_URL'))
  valid = uri.scheme == 'redis' && %w[127.0.0.1 ::1].include?(uri.hostname) && uri.port == 59_511 &&
          uri.userinfo.nil? && ['', '/0'].include?(uri.path) && uri.query.nil? && uri.fragment.nil?
  raise ArgumentError, 'TEST_REDIS_URL requires exclusive loopback:59511/0' unless valid
  unless ENV['POSTGRES_HOST'] == '127.0.0.1' && ENV['POSTGRES_PORT'] == '59510' && ENV['POSTGRES_DATABASE'] == 'chatwoot_test'
    raise ArgumentError, 'Explicit isolated PostgreSQL on loopback:59510/chatwoot_test required'
  end
  raise ArgumentError, 'DATABASE_URL override forbidden' if ENV.key?('DATABASE_URL')
  raise ArgumentError, 'REDIS_URL must match TEST_REDIS_URL' unless ENV['REDIS_URL'] == ENV['TEST_REDIS_URL']
end
raise ArgumentError, 'Only RAILS_ENV=test allowed' unless ENV.fetch('RAILS_ENV', 'test') == 'test'

require 'rails_helper'
# Record actual client commands; barriers delay delivery, never replace a result.
module InstagramOperatorIntegrationRecording
  def call(command, config)
    config.custom.fetch(:commands) << command.dup
    result = super
    if command.first.upcase == 'GET' && command[1] == Thread.current[:race_key]
      Thread.current[:race_key] = nil
      wait_for_release(Thread.current[:race_gate])
    elsif command.first.upcase == 'SETEX' && Thread.current[:publish_gate]
      gate = Thread.current[:publish_gate]
      Thread.current[:publish_gate] = nil
      wait_for_release(gate)
    end
    result
  end

  def call_pipelined(commands, config)
    config.custom.fetch(:commands).concat(commands.map(&:dup))
    super
  end

  private

  def wait_for_release(gate)
    gate.first << true
    Timeout.timeout(3) { gate.last.pop }
  end
end
# Explicit integration entry point owns real Redis/PostgreSQL safety invariants.
RSpec.describe Instagram::Automation::OperatorControl do # rubocop:disable RSpec/SpecFilePathFormat
  self.use_transactional_tests = false
  before(:context) do # rubocop:disable RSpec/BeforeAfterAll -- availability gate only, no shared state
    skip 'Requires explicit TEST_REDIS_URL; no real proof executed' unless ENV.key?('TEST_REDIS_URL')
  end

  let(:namespace) { "turing-950-#{SecureRandom.hex(8)}" }
  let(:commands) { [] }
  let(:infrastructure) { { clients: [], threads: [] } }
  let(:redis) { client }
  let(:pool) { ConnectionPool.new(size: 3, timeout: 1) { Redis::Namespace.new(namespace, redis: client) } }
  let(:control) { described_class.new }
  let(:current_key) { "#{described_class::ROOT_KEY}:#{namespace}:current" }
  let(:manager_key) { "#{described_class::ROOT_KEY}:#{namespace}:manager" }
  let(:metadata) do
    Instagram::Automation::Metadata::KEYS.zip(['10001', '10002', 'Synthetic App', '12345', '10003']).to_h
  end
  let(:configuration) { Instagram::Testers::Configuration.new(account_id: '0') }
  let(:store) { Instagram::Testers::SessionStore.new(configuration: configuration) }
  let(:session) do
    { 'cookie' => 'c_user=12345; xs=synthetic-session', 'fb_dtsg' => 'synthetic-dtsg', 'lsd' => 'synthetic-lsd',
      'jazoest' => '1234', 'user_id' => '12345', 'user_agent' => 'Synthetic Browser', 'extra_form' => { '__req' => '1' } }
  end
  let(:publisher) { Instagram::Automation::SessionPublisher.new }
  let(:request) do
    { 'type' => 'session', 'operation' => 'publish', 'session' => session, 'expected_version' => nil,
      'captured_at' => 1.second.ago.utc.iso8601(6), 'app_id' => '10001', 'business_id' => '10002',
      'proxy_fingerprint' => configuration.proxy.fingerprint, 'roles_response' => '{"data":{"get_app_roles":{"app_roles":[]}}}',
      'configuration_revision' => Digest::SHA256.hexdigest(metadata.to_json), 'roles_doc_id' => '10003' }
  end

  around do |example|
    with_modified_env('INSTAGRAM_TESTER_SESSION_NAMESPACE' => namespace, 'INSTAGRAM_TESTER_SESSION_SOURCE' => 'managed',
                      'INSTAGRAM_TESTER_PROXY_HOST' => '127.0.0.1', 'INSTAGRAM_TESTER_PROXY_PORT' => '59999',
                      'INSTAGRAM_TESTER_PROXY_IDENTITY' => '192.0.2.10:8080',
                      'INSTAGRAM_TESTER_PROXY_AUTH_MODE' => 'ip', 'INSTAGRAM_TESTER_PROXY_USERNAME' => '',
                      'INSTAGRAM_TESTER_PROXY_PASSWORD' => '', 'ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY' => 'primary-key',
                      'ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY' => 'deterministic-key',
                      'ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT' => 'key-derivation-salt') { example.run }
  end

  before do
    infrastructure[:original_pool] = $alfred # rubocop:disable Style/GlobalVars
    $alfred = pool # rubocop:disable Style/GlobalVars
    infrastructure[:saved_rows] = InstallationConfig.where(name: metadata.keys).map(&:attributes)
    sentinel_names = ["#{GlobalConfig::VERSION}:#{GlobalConfig::KEY_PREFIX}:TURING_UNRELATED",
                      "instagram_testers:session:#{namespace}-keep:pointer", "instagram_testers:outcome:#{namespace}:keep"]
    infrastructure[:sentinels] = sentinel_names.to_h do |kind|
      key = "#{namespace}:#{kind}"
      redis.set(key, "synthetic-#{kind}", ex: 900)
      [key, [redis.get(key), redis.call('PEXPIRETIME', key)]]
    end
  end

  after do
    infrastructure[:threads].each do |thread|
      thread.kill if thread.alive?
      thread.join(1)
    end
    # All examples must verify namespace isolation and exact sentinel expiration.
    # rubocop:disable RSpec/ExpectInHook
    expect(commands.map { |command| command.first.upcase }).not_to include('KEYS', 'SCAN', 'ACL', 'FLUSHDB', 'FLUSHALL', 'CONFIG')
    infrastructure[:sentinels].each do |key, expected|
      expect([redis.get(key), redis.call('PEXPIRETIME', key)]).to eq(expected)
    end
    # rubocop:enable RSpec/ExpectInHook
  ensure
    if infrastructure[:original_pool]
      InstallationConfig.where(name: metadata.keys).delete_all
      # Restore exact serialized rows/IDs/timestamps without callbacks changing the snapshot.
      # rubocop:disable Rails/SkipsModelValidations
      InstallationConfig.insert_all!(infrastructure[:saved_rows]) if infrastructure[:saved_rows].any?
      # rubocop:enable Rails/SkipsModelValidations
      # Names are exact, including failed candidate payloads recorded before CAS.
      owned = commands.filter_map { |command| command[1] if %w[SET SETEX EXPIRE].include?(command.first.upcase) }
      redis.del(*(owned + infrastructure[:sentinels].keys).uniq) if redis.connected?
      $alfred = infrastructure[:original_pool] # rubocop:disable Style/GlobalVars
      pool.shutdown { |connection| connection.redis.close }
      infrastructure[:clients].each(&:close)
    end
  end

  def client
    Redis.new(url: ENV.fetch('TEST_REDIS_URL'), timeout: 1, reconnect_attempts: 0,
              middlewares: [InstagramOperatorIntegrationRecording], custom: { commands: commands }).tap do |connection|
      infrastructure[:clients] << connection
    end
  end

  def worker(&)
    thread = Thread.new do
      Thread.current.report_on_exception = false
      ActiveRecord::Base.connection_pool.with_connection(&)
    end
    infrastructure[:threads] << thread
    thread
  end

  def bounded(&)
    Timeout.timeout(3, &)
  end

  # Two live clients, a read barrier and bounded joins are necessary to prove the CAS race.
  def race # rubocop:disable Metrics/AbcSize
    ready = Queue.new
    release = Queue.new
    identities = Queue.new
    contenders = Array.new(2) do
      worker do
        Thread.current[:race_key] = "#{namespace}:#{current_key}"
        Thread.current[:race_gate] = [ready, release]
        pool.with do |connection|
          identities << connection.call('CLIENT', 'ID')
          yield
        end
      rescue Instagram::Automation::OperatorControl::Rejected
        :rejected
      end
    end
    bounded { 2.times { ready.pop } }
    expect(Array.new(2) { identities.pop }.uniq.size).to eq(2)
    2.times { release << true }
    contenders.map { |thread| bounded { thread.value } }
  end

  def running
    control.heartbeat(state: 'operator_required', control_available: true)
    control.enqueue(actor_id: 1).fetch('id').tap { |id| control.claim(id) }
  end
  it 'enqueues on two connections with one CAS winner, reuses active work and closes completed retries' do
    control.heartbeat(state: 'operator_required', control_available: true)
    results = race { described_class.new.enqueue(actor_id: 1) }
    expect(results.count(:rejected)).to eq(1)
    id = results.find { |result| result.is_a?(Hash) }.fetch('id')
    expect(control.enqueue(actor_id: 2).fetch('id')).to eq(id)
    control.claim(id)
    control.complete(id, 'failed')
    expect { control.enqueue(actor_id: 1, id: id) }.to raise_error(described_class::Rejected)
    expect(control.read.fetch('request')).to include('id' => id, 'state' => 'failed')
  end

  it 'permits exactly one concurrent claim through real WATCH/MULTI' do
    control.heartbeat(state: 'operator_required', control_available: true)
    id = control.enqueue(actor_id: 1).fetch('id')
    results = race { described_class.new.claim(id) }
    expect(results.count(:rejected)).to eq(1)
    expect(control.read.fetch('request')).to include('id' => id, 'state' => 'running')
  end

  it 'keeps absent, corrupt, unbounded TTL and expired heartbeats unknown' do
    expect(control.status[:manager_connectivity]).to eq('unknown')
    control.heartbeat(state: 'healthy', control_available: false)
    raw = Redis::Alfred.get(manager_key)
    [['false', 900], ['{', 900], [raw, nil],
     [JSON.parse(raw).merge('observed_at' => 20.minutes.ago.utc.iso8601(3)).to_json, 900]].each do |value, ttl|
      ttl ? Redis::Alfred.set(manager_key, value, ex: ttl) : Redis::Alfred.set(manager_key, value)
      expect(control.status).to include(manager_connectivity: 'unknown', control_available: false)
      expect { control.enqueue(actor_id: 1) }.to raise_error(described_class::Rejected)
    end
    Redis::Alfred.expire(manager_key, 0)
    expect(control.status[:manager_connectivity]).to eq('unknown')
  end

  it 'publishes encrypted SessionStore through the same pool without nesting WATCH' do
    Instagram::Automation::Metadata.new.update!(metadata)
    id = running
    version = control.with_publication(id) do
      store.publish(**request.slice('session', 'expected_version', 'captured_at',
                                    'app_id', 'business_id', 'proxy_fingerprint').symbolize_keys)
    end
    expect(control.read.fetch('request')['state']).to eq('succeeded')
    expect(store.current_snapshot).to eq(session: session, version: version)
    expect(Redis::Alfred.get(store.send(:payload_key, version))).not_to include('synthetic-session')
    transaction_commands = commands.map { |command| command.first.upcase }.select { |name| %w[WATCH MULTI EXEC UNWATCH].include?(name) }
    expect(transaction_commands.each_cons(2).to_a).not_to include(%w[WATCH WATCH])
  end

  it 'rejects stale sessions and replaced requests without confirming success' do
    Instagram::Automation::Metadata.new.update!(metadata)
    id = running
    publisher.call(request)
    expect { control.with_publication(id) { publisher.call(request)[:version] } }.to raise_error(Instagram::Testers::Error)
    expect(control.read.fetch('request')['state']).to eq('running')
    expect do
      control.with_publication(id) do
        result = publisher.call(request.merge('expected_version' => store.current_version, 'captured_at' => Time.current.utc.iso8601(6)))
        control.complete(id, 'failed')
        control.enqueue(actor_id: 2)
        result[:version]
      end
    end.to raise_error(described_class::Rejected)
    expect(control.read.fetch('request')).to include('state' => 'queued')
    expect(control.read.fetch('request')['id']).not_to eq(id)
    expired = control.read.fetch('request').merge('state' => 'running', 'created_at' => 1.minute.ago.utc.iso8601(3),
                                                  'expires_at' => 1.second.ago.utc.iso8601(3))
    Redis::Alfred.set(current_key, expired.to_json, ex: 900)
    expect { control.with_publication(expired.fetch('id')) { raise 'unexpected publication' } }.to raise_error(described_class::Rejected)
  end

  it 'bootstraps persisted metadata, fences a writer during publication and rejects its old revision' do
    Instagram::Automation::Metadata.new.update!(metadata)
    with_modified_env('INSTAGRAM_META_DEVELOPER_APP_ID' => '99999') do
      expect(publisher.call('type' => 'session', 'operation' => 'bootstrap')[:metadata]).to eq(metadata)
    end
    ready = Queue.new
    release = Queue.new
    publication = worker do
      Thread.current[:publish_gate] = [ready, release]
      publisher.call(request)
    end
    bounded { ready.pop }
    writer = worker do
      InstallationConfig.transaction do
        ActiveRecord::Base.connection.execute("SET LOCAL lock_timeout = '300ms'")
        Instagram::Automation::Metadata.new.update!(metadata.merge('INSTAGRAM_META_DEVELOPER_APP_ID' => '20001',
                                                                   'INSTAGRAM_TESTER_ADMIN_USER_ID' => '54321'))
      end
    rescue ActiveRecord::StatementInvalid => e
      e.cause.class.name
    end
    expect(bounded { writer.value }).to eq('PG::LockNotAvailable')
    release << true
    expect(bounded { publication.value }[:version]).to eq(store.current_version)
    updated = metadata.merge('INSTAGRAM_META_DEVELOPER_APP_ID' => '20001', 'INSTAGRAM_TESTER_ADMIN_USER_ID' => '54321')
    Instagram::Automation::Metadata.new.update!(updated)
    expect(publisher.call('type' => 'session', 'operation' => 'bootstrap')[:metadata]).to eq(updated)
    expect { publisher.call(request.merge('expected_version' => store.current_version)) }.to raise_error(Instagram::Testers::Error)
  end

  it 'exposes only complete committed metadata during a concurrent transactional save' do
    Instagram::Automation::Metadata.new.update!(metadata)
    updated = metadata.merge('INSTAGRAM_META_DEVELOPER_APP_ID' => '20001', 'INSTAGRAM_TESTER_ADMIN_USER_ID' => '54321')
    ready = Queue.new
    release = Queue.new
    writer = worker do
      InstallationConfig.transaction do
        Instagram::Automation::Metadata.new.update!(updated)
        ready << true
        bounded { release.pop }
      end
    end
    bounded { ready.pop }
    expect(Instagram::Automation::Metadata.new.values).to eq(metadata)
    release << true
    bounded { writer.value }
    expect(publisher.call('type' => 'session', 'operation' => 'bootstrap')[:metadata]).to eq(updated)
  end
end
