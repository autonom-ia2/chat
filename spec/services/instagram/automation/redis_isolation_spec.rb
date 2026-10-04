# Opt-in only: the parent owns this disposable server. Never fall back to REDIS_URL.
if ENV.key?('TEST_REDIS_URL') && ENV.fetch('TEST_REDIS_URL') != 'redis://127.0.0.1:59511/0'
  raise ArgumentError, 'TEST_REDIS_URL must be exactly redis://127.0.0.1:59511/0'
end
raise ArgumentError, 'Only RAILS_ENV=test is allowed' unless ENV.fetch('RAILS_ENV', 'test') == 'test'

require 'rails_helper'

# Client-local recording; every command and result still goes through real Redis.
module InstagramAutomationCacheRedisRecording
  def call(command, config)
    config.custom.fetch(:commands) << command.dup
    super
  end

  def call_pipelined(commands, config)
    config.custom.fetch(:commands).concat(commands.map(&:dup))
    super
  end
end

RSpec.describe GlobalConfig do # rubocop:disable RSpec/SpecFilePathFormat -- explicit Instagram integration entry point
  self.use_transactional_tests = false

  before(:context) do # rubocop:disable RSpec/BeforeAfterAll -- availability gate only; no shared setup or records
    skip 'Real Redis proof requires explicit TEST_REDIS_URL; no connection or assertion was executed' unless ENV.key?('TEST_REDIS_URL')
  end

  let(:namespace) { "instagram-automation-cache-spec:#{SecureRandom.hex(8)}" }
  let(:prefix) { "#{described_class::VERSION}:#{described_class::KEY_PREFIX}" }
  let(:config_names) { %w[A B C DEFAULT].map { |suffix| "#{namespace}_#{suffix}" } }
  let(:name_a) { config_names[0] }
  let(:name_b) { config_names[1] }
  let(:name_c) { config_names[2] }
  let(:default_name) { config_names[3] }
  let(:commands) { [] }
  let(:redis) do
    Redis.new(url: ENV.fetch('TEST_REDIS_URL'), timeout: 2, reconnect_attempts: 0,
              middlewares: [InstagramAutomationCacheRedisRecording], custom: { commands: commands })
  end
  let(:alfred) { Redis::Namespace.new(namespace, redis: redis, warning: true) }
  let(:original_pool) { $alfred } # rubocop:disable Style/GlobalVars -- production cache pool interface
  let(:test_pool) { ConnectionPool.new(size: 1, timeout: 1) { alfred } }
  let(:sentinels) do
    {
      "#{namespace}:#{prefix}:UNRELATED" => ['{"value":"keep"}', 900],
      "#{namespace}:operator:lock" => ['synthetic-lock', 300],
      "#{namespace}:operator:session" => ['synthetic-session', 600],
      "#{namespace}:operator:persistent" => ['synthetic-persistent', nil],
      "#{namespace}-outside:#{prefix}:sentinel" => ['synthetic-outside', 900]
    }
  end
  let(:owned_keys) { sentinels.keys + (config_names + ['*']).map { |name| "#{namespace}:#{prefix}:#{name}" } }

  before do
    original_pool
    sentinels.each do |key, metadata|
      value, ttl = metadata
      ttl ? redis.set(key, value, ex: ttl) : redis.set(key, value)
      # Absolute expiry avoids timing tolerances hiding a changed TTL.
      metadata << redis.call('PEXPIRETIME', key)
    end
    $alfred = test_pool # rubocop:disable Style/GlobalVars -- production cache pool interface
    commands.clear
  end

  after do
    # Restore before the suite-wide legacy cache cleanup hook runs.
    $alfred = original_pool # rubocop:disable Style/GlobalVars -- restore production cache pool interface
    begin
      InstallationConfig.where(name: config_names).delete_all
      redis.del(*owned_keys) if redis.connected?
    ensure
      test_pool.shutdown { |connection| connection.redis.close }
      redis.close
    end
  end

  context 'with targeted invalidation' do
    # Common safety invariants must hold for every targeted operation, including new examples.
    # rubocop:disable RSpec/ExpectInHook
    after do
      expect(commands.map { |command| command.first.upcase }).not_to include('KEYS', 'SCAN', 'FLUSHDB', 'FLUSHALL')
      sentinels.each do |key, (value, _ttl, expiration_time)|
        expect(redis.get(key)).to eq(value)
        expect(redis.call('PEXPIRETIME', key)).to eq(expiration_time)
      end
    end
    # rubocop:enable RSpec/ExpectInHook

    it 'expires multiple literal names, deduplicates them and keeps an explicit nil targeted' do
      [name_a, name_b, '*'].each { |name| alfred.set("#{prefix}:#{name}", '{"value":"old"}', ex: 600) }

      described_class.clear_cache(name_a, name_b, name_a, nil, '*')
      described_class.clear_cache(nil)

      [name_a, name_b, '*'].each { |name| expect(alfred.get("#{prefix}:#{name}")).to be_nil }
      expirations = commands.select { |command| command.first.upcase == 'EXPIRE' }
      expect(expirations.map { |command| command[1] }).to eq([name_a, name_b, '*'].map { |name| "#{namespace}:#{prefix}:#{name}" })
      expect(expirations.map { |command| command[2].to_i }).to eq([0, 0, 0])
    end

    it 'invalidates cached misses and values on committed create, update and destroy' do
      expect(described_class.get_value(name_a)).to be_nil
      config = InstallationConfig.create!(name: name_a, value: 'created')
      expect(described_class.get_value(name_a)).to eq('created')

      config.update!(value: 'updated')
      expect(described_class.get_value(name_a)).to eq('updated')

      config.destroy!
      expect(described_class.get_value(name_a)).to be_nil
      expect(InstallationConfig.exists?(config.id)).to be false
    end

    it 'invalidates A, cached B and a cached miss for C after A to B to C in one transaction' do
      config = InstallationConfig.create!(name: name_a, value: 'before')
      expect(described_class.get_value(name_a)).to eq('before')
      expect(described_class.get_value(name_c)).to be_nil

      InstallationConfig.transaction do
        config.update!(name: name_b)
        expect(described_class.get_value(name_b)).to eq('before')
        config.update!(name: name_c, value: 'after')
        expect(described_class.get_value(name_a)).to eq('before')
        expect(described_class.get_value(name_c)).to be_nil
      end

      expect([name_a, name_b, name_c].map { |name| described_class.get_value(name) }).to eq([nil, nil, 'after'])
    end

    it 'drops rolled-back callbacks and leaves no name history on the reused record' do
      config = InstallationConfig.create!(name: name_a, value: 'before')
      expect(described_class.get_value(name_a)).to eq('before')
      [name_b, name_c].each { |name| alfred.set("#{prefix}:#{name}", '{"value":"keep"}', ex: 600) }
      commands.clear

      InstallationConfig.transaction do
        config.update!(name: name_b)
        config.update!(name: name_c, value: 'rolled back')
        raise ActiveRecord::Rollback
      end

      expect(commands.map(&:first)).not_to include('expire', 'EXPIRE')
      expect(InstallationConfig.find(config.id).name).to eq(name_a)
      expect(described_class.get_value(name_a)).to eq('before')
      config.update!(name: name_a, value: 'committed')

      expect(described_class.get_value(name_a)).to eq('committed')
      [name_b, name_c].each { |name| expect(described_class.get_value(name)).to eq('keep') }
      expired_keys = commands.select { |command| command.first.upcase == 'EXPIRE' }.map { |command| command[1] }
      expect(expired_keys.uniq).to eq(["#{namespace}:#{prefix}:#{name_a}"])
    end

    it 'preserves C and its exact expiry after a savepoint rollback and a subsequent parent write' do
      config = InstallationConfig.create!(name: name_a, value: 'before')
      expect(described_class.get_value(name_a)).to eq('before')
      alfred.set("#{prefix}:#{name_c}", '{"value":"keep C"}', ex: 600)
      c_key = "#{namespace}:#{prefix}:#{name_c}"
      c_expiration = redis.call('PEXPIRETIME', c_key)
      commands.clear

      InstallationConfig.transaction do
        config.update!(name: name_b)
        expect(described_class.get_value(name_b)).to eq('before')
        InstallationConfig.transaction(requires_new: true) do
          config.update!(name: name_c)
          raise ActiveRecord::Rollback
        end
        expect(InstallationConfig.unscoped.where(id: config.id).pick(:name)).to eq(name_b)
        config.update!(name: name_b, value: 'committed')
      end

      expect([name_a, name_b, name_c].map { |name| described_class.get_value(name) }).to eq([nil, 'committed', 'keep C'])
      expect(redis.call('PEXPIRETIME', c_key)).to eq(c_expiration)
      expired_keys = commands.select { |command| command.first.upcase == 'EXPIRE' }.map { |command| command[1] }
      expect(expired_keys.uniq).to match_array([name_a, name_b].map { |name| "#{namespace}:#{prefix}:#{name}" })
    end

    it 'invalidates all committed renames when destroying in the same transaction' do
      config = InstallationConfig.create!(name: name_a, value: 'before')
      expect(described_class.get_value(name_a)).to eq('before')

      InstallationConfig.transaction do
        config.update!(name: name_b)
        expect(described_class.get_value(name_b)).to eq('before')
        config.update!(name: name_c)
        expect(described_class.get_value(name_c)).to eq('before')
        config.destroy!
      end

      [name_a, name_b, name_c].each { |name| expect(described_class.get_value(name)).to be_nil }
    end

    it 'invalidates the persisted and unsaved names on destroy' do
      config = InstallationConfig.create!(name: name_a, value: 'before')
      expect(described_class.get_value(name_a)).to eq('before')
      config.reload
      config.name = name_b
      alfred.set("#{prefix}:#{name_b}", '{"value":"old"}')

      config.destroy!

      [name_a, name_b].each { |name| expect(alfred.get("#{prefix}:#{name}")).to be_nil }
    end

    it 'invalidates only the default-loaded name after a cached miss' do
      expect(described_class.get_value(default_name)).to be_nil

      expect(GlobalConfigService.load(default_name, 'default')).to eq('default')

      expect(described_class.get_value(default_name)).to eq('default')
      expect(InstallationConfig.find_by!(name: default_name).value).to eq('default')
    end

    it 'invalidates a cached miss when default load finds an existing record' do
      InstallationConfig.create!(name: default_name, value: 'existing')
      alfred.set("#{prefix}:#{default_name}", '{"value":null}', ex: 600)

      expect(GlobalConfigService.load(default_name, 'default')).to eq('existing')

      expect(described_class.get_value(default_name)).to eq('existing')
    end
  end

  it 'preserves legacy global clear without arguments within the Alfred GlobalConfig namespace' do
    alfred.set("#{prefix}:#{name_a}", '{"value":"old"}')

    described_class.clear_cache

    expect(alfred.get("#{prefix}:#{name_a}")).to be_nil
    expect(alfred.get("#{prefix}:UNRELATED")).to be_nil
    expect(commands).to include(['keys', "#{namespace}:#{prefix}:*"])
    sentinels.except("#{namespace}:#{prefix}:UNRELATED").each do |key, (value, _ttl, expiration_time)|
      expect(redis.get(key)).to eq(value)
      expect(redis.call('PEXPIRETIME', key)).to eq(expiration_time)
    end
  end
end
