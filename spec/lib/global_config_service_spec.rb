require 'rails_helper'

describe GlobalConfigService do
  subject(:trigger) { described_class }

  describe 'execute' do
    context 'when called with default options' do
      before do
        # to clear redis cache
        GlobalConfig.clear_cache
      end

      # it 'set default value if not found on db nor env var' do
      #   value = GlobalConfig.get('ENABLE_ACCOUNT_SIGNUP')
      #   expect(value['ENABLE_ACCOUNT_SIGNUP']).to eq nil

      #   described_class.load('ENABLE_ACCOUNT_SIGNUP', 'true')

      #   value = GlobalConfig.get('ENABLE_ACCOUNT_SIGNUP')
      #   expect(value['ENABLE_ACCOUNT_SIGNUP']).to eq 'true'
      #   expect(InstallationConfig.find_by(name: 'ENABLE_ACCOUNT_SIGNUP')&.value).to eq 'true'
      # end

      it 'get value from env variable even if present on DB' do
        with_modified_env ENABLE_ACCOUNT_SIGNUP: 'false' do
          expect(InstallationConfig.find_by(name: 'ENABLE_ACCOUNT_SIGNUP')&.value).to be_nil
          value = described_class.load('ENABLE_ACCOUNT_SIGNUP', 'true')
          expect(value).to eq 'false'
        end
      end

      # it 'get value from DB if found' do
      #   # Set a value in db first and make sure this value
      #   # is not respected even when load() method is called with
      #   # another value.
      #   InstallationConfig.where(name: 'ENABLE_ACCOUNT_SIGNUP').first_or_create(value: 'true')
      #   described_class.load('ENABLE_ACCOUNT_SIGNUP', 'false')
      #   value = GlobalConfig.get('ENABLE_ACCOUNT_SIGNUP')
      #   expect(value['ENABLE_ACCOUNT_SIGNUP']).to eq 'true'
      # end
    end
  end

  describe '.load cache invalidation' do
    let(:redis) { Redis::Alfred.with { |conn| conn } }
    let(:prefix) { "#{GlobalConfig::VERSION}:#{GlobalConfig::KEY_PREFIX}" }

    before do
      GlobalConfig.clear_cache
      redis.set("#{prefix}:UNRELATED", { value: 'keep' }.to_json)
      allow(redis).to receive(:keys).and_call_original
      allow(redis).to receive(:scan).and_call_original
    end

    it 'clears only the loaded key when creating a default after a cached miss' do
      expect(GlobalConfig.get_value('CACHE_SERVICE_TARGET')).to be_nil

      expect(described_class.load('CACHE_SERVICE_TARGET', 'default')).to eq('default')

      expect(GlobalConfig.get_value('CACHE_SERVICE_TARGET')).to eq('default')
      expect(GlobalConfig.get_value('UNRELATED')).to eq('keep')
      expect(redis).not_to have_received(:keys)
      expect(redis).not_to have_received(:scan)
    end

    it 'clears a cached miss even when first_or_create finds an existing record' do
      create(:installation_config, name: 'CACHE_SERVICE_TARGET', value: 'existing')
      redis.set("#{prefix}:CACHE_SERVICE_TARGET", { value: nil }.to_json)

      expect(described_class.load('CACHE_SERVICE_TARGET', 'default')).to eq('existing')

      expect(GlobalConfig.get_value('CACHE_SERVICE_TARGET')).to eq('existing')
      expect(GlobalConfig.get_value('UNRELATED')).to eq('keep')
      expect(redis).not_to have_received(:keys)
      expect(redis).not_to have_received(:scan)
    end
  end
end
