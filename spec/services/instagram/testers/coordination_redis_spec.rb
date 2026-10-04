require 'rails_helper'

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

  it 'requires an explicit TLS endpoint and certificate verification without reconnection retries' do
    with_modified_env INSTAGRAM_TESTER_COORDINATION_REDIS_URL: 'rediss://:synthetic@coordination.invalid:6379/0' do
      expect(described_class.configured?).to be true
      connection = instance_double(Redis, get: nil)
      expect(Redis).to receive(:new).with(url: 'rediss://:synthetic@coordination.invalid:6379/0', timeout: 2,
                                          reconnect_attempts: 0, ssl_params: { verify_mode: OpenSSL::SSL::VERIFY_PEER }).and_return(connection)
      expect(described_class.get('synthetic')).to be_nil
    end
  end
end
