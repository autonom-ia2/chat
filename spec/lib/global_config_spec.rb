require 'rails_helper'

describe GlobalConfig do
  subject(:trigger) { described_class }

  describe 'execute' do
    context 'when called with default options' do
      before do
        described_class.clear_cache
      end

      it 'hit DB for the first call' do
        expect(InstallationConfig).to receive(:find_by)
        described_class.get('test')
      end

      it 'get from cache for subsequent calls' do
        # this loads from DB
        described_class.get('test')

        # subsequent calls should not hit DB
        expect(InstallationConfig).not_to receive(:find_by)
        described_class.get('test')
      end

      it 'clears cache and fetch from DB next time, when clear_cache is called' do
        # this loads from DB and is cached
        described_class.get('test')

        # clears the cache
        described_class.clear_cache

        # should be loaded from DB
        expect(InstallationConfig).to receive(:find_by).with({ name: 'test' }).and_return(nil)
        described_class.get('test')
      end
    end
  end

  describe '.clear_cache' do
    let(:redis) { Redis::Alfred.with { |conn| conn } }
    let(:prefix) { "#{described_class::VERSION}:#{described_class::KEY_PREFIX}" }

    before do
      described_class.clear_cache
      redis.set("#{prefix}:UNRELATED", { value: 'keep' }.to_json)
      allow(redis).to receive(:keys).and_call_original
      allow(redis).to receive(:scan).and_call_original
    end

    it 'invalidates only the requested name without enumerating Redis keys' do
      redis.set("#{prefix}:TARGET", { value: 'old' }.to_json)

      described_class.clear_cache('TARGET')

      expect(redis.get("#{prefix}:TARGET")).to be_nil
      expect(described_class.get_value('UNRELATED')).to eq('keep')
      expect(redis).not_to have_received(:keys)
      expect(redis).not_to have_received(:scan)
    end

    it 'invalidates multiple names, ignoring duplicate and nil names' do
      redis.set("#{prefix}:OLD_NAME", { value: 'old' }.to_json)
      redis.set("#{prefix}:NEW_NAME", { value: nil }.to_json)

      described_class.clear_cache('OLD_NAME', 'NEW_NAME', 'OLD_NAME', nil)

      expect(redis.get("#{prefix}:OLD_NAME")).to be_nil
      expect(redis.get("#{prefix}:NEW_NAME")).to be_nil
      expect(described_class.get_value('UNRELATED')).to eq('keep')
      expect(redis).not_to have_received(:keys)
      expect(redis).not_to have_received(:scan)
    end

    it 'does not turn an explicit nil name into a global clear' do
      described_class.clear_cache(nil)

      expect(described_class.get_value('UNRELATED')).to eq('keep')
      expect(redis).not_to have_received(:keys)
      expect(redis).not_to have_received(:scan)
    end

    it 'treats a name containing a wildcard as a literal key' do
      redis.set("#{prefix}:*", { value: 'literal' }.to_json)

      described_class.clear_cache('*')

      expect(redis.get("#{prefix}:*")).to be_nil
      expect(described_class.get_value('UNRELATED')).to eq('keep')
      expect(redis).not_to have_received(:keys)
      expect(redis).not_to have_received(:scan)
    end

    it 'preserves the global clear without arguments and its namespace boundary' do
      redis.set("#{prefix}:TARGET", { value: 'old' }.to_json)
      redis.set('OTHER_CACHE:TARGET', 'keep')

      described_class.clear_cache

      expect(redis.get("#{prefix}:TARGET")).to be_nil
      expect(redis.get("#{prefix}:UNRELATED")).to be_nil
      expect(redis.get('OTHER_CACHE:TARGET')).to eq('keep')
      expect(redis).to have_received(:keys).with("#{prefix}:*")
      redis.del('OTHER_CACHE:TARGET')
    end
  end
end
