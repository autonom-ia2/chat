require 'spec_helper'
require 'climate_control'

ENV['RAILS_ENV'] ||= 'test'
require_relative '../../../../config/environment'
abort('The Rails environment is running in production mode!') if Rails.env.production?

RSpec.describe Instagram::Testers::CoordinationRedis do
  it 'shares the isolated application test Redis when no dedicated connection is configured' do
    with_modified_env INSTAGRAM_TESTER_COORDINATION_REDIS_URL: nil do
      described_class.set('instagram-test-synthetic-key', 'synthetic', nx: true, ex: 30)
      expect(described_class.get('instagram-test-synthetic-key')).to eq('synthetic')
      described_class.delete_if_equals('instagram-test-synthetic-key', 'wrong')
      expect(described_class.get('instagram-test-synthetic-key')).to eq('synthetic')
      described_class.delete_if_equals('instagram-test-synthetic-key', 'synthetic')
      expect(described_class.get('instagram-test-synthetic-key')).to be_nil
    end
  end

  ['', 'redis://localhost:6379', 'rediss://localhost:6379', 'rediss://:synthetic@localhost:6379/0?',
   'rediss://:synthetic@localhost:6379/0#', 'rediss://:synthetic@localhost:6379/?unsafe=true'].each do |url|
    it 'rejects a missing, plaintext or malformed production coordination endpoint' do
      with_modified_env INSTAGRAM_TESTER_COORDINATION_REDIS_URL: url do
        expect(described_class.configured?).to be false
      end
    end
  end

  it 'never falls back to installation Redis in production with a missing coordinator' do
    allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))
    with_modified_env INSTAGRAM_TESTER_COORDINATION_REDIS_URL: nil, INSTAGRAM_TESTER_COORDINATION_EPOCH: nil do
      expect(Redis::Alfred).not_to receive(:with)
      expect { described_class.get('synthetic') }.to(raise_error { |error| expect(error.code).to eq('meta_unavailable') })
    end
  end

  context 'with a dedicated connection' do
    let(:url) { 'rediss://:synthetic@coordination.invalid:6379/0' }
    let(:epoch) { 'synthetic-epoch-2026' }
    let(:connection) { instance_double(Redis) }

    around do |example|
      with_modified_env INSTAGRAM_TESTER_COORDINATION_REDIS_URL: url,
                        INSTAGRAM_TESTER_COORDINATION_EPOCH: epoch,
                        INSTAGRAM_TESTER_COORDINATION_REDIS_CA_FILE: nil do
        example.run
      end
    end

    before do
      described_class.instance_variable_set(:@pools, {})
      allow(Redis).to receive(:new).and_return(connection)
      allow(connection).to receive(:get).with('instagram_tester_coordination:integrity:epoch').and_return(epoch)
    end

    it 'requires TLS certificate verification with system trust and no reconnection retries' do
      expect(described_class.configured?).to be true
      expect(Redis).to receive(:new).with(url: url, timeout: 2, reconnect_attempts: 0,
                                          ssl_params: { verify_mode: OpenSSL::SSL::VERIFY_PEER }).and_return(connection)
      expect(connection).to receive(:get).with('instagram_tester_coordination:synthetic').and_return(nil)
      expect(described_class.get('synthetic')).to be_nil
    end

    [nil, '', 'short', 'x' * 129, 'x' * 15, 'synthetic epoch 2026', "synthetic-epoch-\n2026",
     'synthetic-époch-2026', 'synthetic:epoch:2026'].each do |invalid_epoch|
      it "rejects an unsafe or absent configured epoch (#{invalid_epoch.inspect})" do
        with_modified_env INSTAGRAM_TESTER_COORDINATION_EPOCH: invalid_epoch do
          expect(described_class.configured?).to be false
          expect(Redis).not_to receive(:new)
          expect { described_class.get('synthetic') }.to(raise_error { |error| expect(error.code).to eq('meta_unavailable') })
        end
      end
    end

    ['a' * 16, 'Z' * 128, 'Abc_1234-def.5678'].each do |valid_epoch|
      it 'accepts bounded ASCII letters, digits, underscore, dot and hyphen' do
        with_modified_env INSTAGRAM_TESTER_COORDINATION_EPOCH: valid_epoch do
          expect(described_class.configured?).to be true
        end
      end
    end

    [nil, 'different-epoch-2026'].each do |stored_epoch|
      it 'blocks a missing or mismatched persisted epoch without initializing it' do
        allow(connection).to receive(:get).with('instagram_tester_coordination:integrity:epoch').and_return(stored_epoch)
        expect(connection).not_to receive(:set)
        expect { described_class.set('synthetic', 'value', nx: true, ex: 90) }
          .to(raise_error { |error| expect(error.code).to eq('meta_unavailable') })
      end
    end

    it 'checks again on a reused pool and blocks a newly empty volume' do
      expect(connection).to receive(:get).with('instagram_tester_coordination:integrity:epoch').ordered.and_return(epoch)
      expect(connection).to receive(:get).with('instagram_tester_coordination:synthetic').ordered.and_return('previous-volume')
      expect(described_class.get('synthetic')).to eq('previous-volume')
      expect(connection).to receive(:get).with('instagram_tester_coordination:integrity:epoch').ordered.and_return(nil)
      expect(connection).not_to receive(:set)
      expect { described_class.get('synthetic') }.to(raise_error { |error| expect(error.code).to eq('meta_unavailable') })
    end

    it 'uses a regular absolute CA file with peer verification' do
      Tempfile.create('instagram-coordination-ca') do |file|
        with_modified_env INSTAGRAM_TESTER_COORDINATION_REDIS_CA_FILE: file.path do
          expect(described_class.configured?).to be true
          expect(Redis).to receive(:new).with(url: url, timeout: 2, reconnect_attempts: 0,
                                              ssl_params: { ca_file: file.path, verify_mode: OpenSSL::SSL::VERIFY_PEER }).and_return(connection)
          described_class.with { |redis| expect(redis.redis).to eq(connection) }
        end
      end
    end

    ['relative-ca.pem', '/missing-instagram-coordination-ca.pem', Dir.tmpdir].each do |path|
      it 'rejects relative, absent or non-file CA paths before connecting' do
        with_modified_env INSTAGRAM_TESTER_COORDINATION_REDIS_CA_FILE: path do
          expect(described_class.configured?).to be false
          expect(Redis).not_to receive(:new)
          expect { described_class.get('synthetic') }.to(raise_error { |error| expect(error.code).to eq('meta_unavailable') })
        end
      end
    end

    it 'rejects a CA symlink even when its target is a regular file' do
      Dir.mktmpdir('instagram-ca') do |directory|
        file = File.join(directory, 'ca.pem')
        link = File.join(directory, 'linked-ca.pem')
        File.write(file, 'synthetic certificate')
        File.symlink(file, link)
        with_modified_env INSTAGRAM_TESTER_COORDINATION_REDIS_CA_FILE: link do
          expect(described_class.configured?).to be false
          expect(Redis).not_to receive(:new)
          expect { described_class.get('synthetic') }.to(raise_error { |error| expect(error.code).to eq('meta_unavailable') })
        end
      end
    end

    it 'creates a different pool when the CA path changes for the same URL' do
      described_class.with { |_redis| nil }
      Tempfile.create('instagram-coordination-ca') do |file|
        with_modified_env INSTAGRAM_TESTER_COORDINATION_REDIS_CA_FILE: file.path do
          described_class.with { |_redis| nil }
        end
      end
      expect(Redis).to have_received(:new).twice
    end

    it 'creates a different pool when connection credentials change' do
      described_class.with { |_redis| nil }
      with_modified_env INSTAGRAM_TESTER_COORDINATION_REDIS_URL: 'rediss://:other-synthetic@coordination.invalid:6379/0' do
        described_class.with { |_redis| nil }
      end
      expect(Redis).to have_received(:new).twice
    end

    it 'sets NX EX then waits for local AOF fsync on the same connection' do
      expect(connection).to receive(:set).with('instagram_tester_coordination:synthetic', 'unknown:claim', nx: true, ex: 86_400)
                                         .ordered.and_return(true)
      expect(connection).to receive(:call).with(['WAITAOF', 1, 0, 2000]).ordered.and_return([1, 0])
      expect(described_class.durable_set('synthetic', 'unknown:claim', ex: 86_400)).to be true
      expect(Redis).to have_received(:new).once
    end

    it 'does not wait when another worker already owns the claim' do
      expect(connection).to receive(:set).and_return(false)
      expect(connection).not_to receive(:call)
      expect(described_class.durable_set('synthetic', 'unknown:claim', ex: 86_400)).to be false
    end

    it 'blocks when WAITAOF times out without a local fsync acknowledgement' do
      allow(connection).to receive(:set).and_return(true)
      expect(connection).to receive(:call).with(['WAITAOF', 1, 0, 2000]).and_return([0, 0])
      expect(connection).not_to receive(:del)
      expect { described_class.durable_set('synthetic', 'unknown:claim', ex: 86_400) }
        .to(raise_error { |error| expect(error.code).to eq('invite_unknown') })
    end

    [Redis::TimeoutError, Redis::CommandError].each do |failure|
      it 'blocks on a network timeout or unsupported WAITAOF without exposing connection errors' do
        allow(connection).to receive(:set).and_return(true)
        allow(connection).to receive(:call).and_raise(failure, 'synthetic failure')
        expect(connection).not_to receive(:del)
        expect { described_class.durable_set('synthetic', 'unknown:claim', ex: 86_400) }.to raise_error do |error|
          expect(error.code).to eq('invite_unknown')
          expect(error.cause).to be_nil
        end
      end
    end

    it 'preserves the ordinary lock SET without waiting for AOF' do
      expect(connection).to receive(:set).with('instagram_tester_coordination:lock', 'token', nx: true, ex: 90).and_return(true)
      expect(connection).not_to receive(:call)
      expect(described_class.set('lock', 'token', nx: true, ex: 90)).to be true
    end
  end
end
