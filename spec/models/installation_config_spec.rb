# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InstallationConfig do
  subject(:installation_config) { described_class.new(name: 'INSTALLATION_NAME') }

  it { is_expected.to validate_presence_of(:name) }

  describe 'new record defaults' do
    it 'initializes serialized_value with indifferent access' do
      expect(installation_config.serialized_value).to eq({}.with_indifferent_access)
    end

    it 'returns nil for value before assignment' do
      expect(installation_config.value).to be_nil
    end
  end

  describe 'cache invalidation after commit' do
    self.use_transactional_tests = false

    let(:redis) { Redis::Alfred.with { |conn| conn } }
    let(:prefix) { "#{GlobalConfig::VERSION}:#{GlobalConfig::KEY_PREFIX}" }
    let(:cache_names) { %w[CACHE_TARGET CACHE_RENAMED CACHE_FINAL].map { |name| "#{name}_#{SecureRandom.hex(6)}" } }
    let(:original_name) { cache_names[0] }
    let(:renamed_name) { cache_names[1] }
    let(:final_name) { cache_names[2] }
    let(:config) { create(:installation_config, name: original_name, value: 'before') }

    before do
      GlobalConfig.clear_cache
      redis.set("#{prefix}:UNRELATED", { value: 'keep' }.to_json)
      allow(redis).to receive(:keys).and_call_original
      allow(redis).to receive(:scan).and_call_original
    end

    after do
      described_class.where(name: cache_names).delete_all
    end

    it 'invalidates every saved name after multiple renames in one transaction, including a cached intermediate value' do
      expect([config.name, final_name].map { |name| GlobalConfig.get_value(name) }).to eq(['before', nil])

      described_class.transaction do
        config.update!(name: renamed_name)
        expect(GlobalConfig.get_value(renamed_name)).to eq('before')
        config.update!(name: final_name, value: 'after')
        expect(GlobalConfig.get_value(original_name)).to eq('before')
      end

      expect(cache_names.map { |name| GlobalConfig.get_value(name) }).to eq([nil, nil, 'after'])
      expect(GlobalConfig.get_value('UNRELATED')).to eq('keep')
      expect(redis).not_to have_received(:keys)
      expect(redis).not_to have_received(:scan)
    end

    it 'discards rolled-back renames without carrying their names into the next commit on the same instance' do
      expect(GlobalConfig.get_value(config.name)).to eq('before')
      redis.set("#{prefix}:#{renamed_name}", { value: 'keep B' }.to_json)
      redis.set("#{prefix}:#{final_name}", { value: 'keep C' }.to_json)

      described_class.transaction do
        config.update!(name: renamed_name)
        config.update!(name: final_name, value: 'rolled back')
        raise ActiveRecord::Rollback
      end

      expect(described_class.find(config.id).name).to eq(original_name)
      expect(GlobalConfig.get_value(original_name)).to eq('before')
      config.update!(name: original_name, value: 'committed')

      expect(GlobalConfig.get_value(original_name)).to eq('committed')
      expect(GlobalConfig.get_value(renamed_name)).to eq('keep B')
      expect(GlobalConfig.get_value(final_name)).to eq('keep C')
    end

    it 'drops callbacks for a rolled-back savepoint while invalidating the names committed by the parent' do
      expect(GlobalConfig.get_value(config.name)).to eq('before')
      redis.set("#{prefix}:#{final_name}", { value: 'keep C' }.to_json)

      described_class.transaction do
        config.update!(name: renamed_name)
        expect(GlobalConfig.get_value(renamed_name)).to eq('before')
        described_class.transaction(requires_new: true) do
          config.update!(name: final_name)
          raise ActiveRecord::Rollback
        end
        persisted_name = described_class.unscoped.where(id: config.id).pick(:name)
        RSpec.configuration.reporter.message(
          "Savepoint rollback: #{ { current: config.name, dirty_database: config.name_in_database,
                                    before_last_save: config.name_before_last_save, persisted: persisted_name }.inspect }"
        )
        expect(persisted_name).to eq(renamed_name)
        config.update!(name: renamed_name, value: 'committed')
      end

      expect(GlobalConfig.get_value(original_name)).to be_nil
      expect(GlobalConfig.get_value(renamed_name)).to eq('committed')
      expect(GlobalConfig.get_value(final_name)).to eq('keep C')
    end

    it 'promotes callbacks from a committed savepoint and waits for the parent commit' do
      expect(GlobalConfig.get_value(config.name)).to eq('before')
      expect(GlobalConfig.get_value(final_name)).to be_nil

      described_class.transaction do
        described_class.transaction(requires_new: true) do
          config.update!(name: renamed_name)
          expect(GlobalConfig.get_value(renamed_name)).to eq('before')
          config.update!(name: final_name)
        end
        expect(GlobalConfig.get_value(original_name)).to eq('before')
        expect(GlobalConfig.get_value(final_name)).to be_nil
      end

      expect(cache_names.map { |name| GlobalConfig.get_value(name) }).to eq([nil, nil, 'before'])
    end

    it 'invalidates all names when a multiply renamed record is destroyed in the same transaction' do
      expect(GlobalConfig.get_value(config.name)).to eq('before')

      described_class.transaction do
        config.update!(name: renamed_name)
        expect(GlobalConfig.get_value(renamed_name)).to eq('before')
        config.update!(name: final_name)
        expect(GlobalConfig.get_value(final_name)).to eq('before')
        config.destroy!
      end

      expect(GlobalConfig.get_value(original_name)).to be_nil
      expect(GlobalConfig.get_value(renamed_name)).to be_nil
      expect(GlobalConfig.get_value(final_name)).to be_nil
    end

    it 'keeps the cache on rolled-back destroy and invalidates it on a later committed destroy' do
      expect(GlobalConfig.get_value(config.name)).to eq('before')

      described_class.transaction do
        config.destroy!
        raise ActiveRecord::Rollback
      end

      expect(described_class.exists?(config.id)).to be true
      expect(GlobalConfig.get_value(config.name)).to eq('before')
      config.destroy!
      expect(GlobalConfig.get_value(original_name)).to be_nil
    end

    it 'discards a rolled-back create when reusing the same instance for a different name' do
      expect(GlobalConfig.get_value(original_name)).to be_nil
      expect(GlobalConfig.get_value(renamed_name)).to be_nil
      record = described_class.new(name: original_name, value: 'created')

      described_class.transaction do
        record.save!
        raise ActiveRecord::Rollback
      end

      expect(described_class.exists?(name: original_name)).to be false
      cached_miss = redis.get("#{prefix}:#{original_name}")
      record.update!(name: renamed_name)
      expect(redis.get("#{prefix}:#{original_name}")).to eq(cached_miss)
      expect(GlobalConfig.get_value(renamed_name)).to eq('created')
    end

    it 'invalidates a cached missing name on create and preserves unrelated cached values' do
      expect(GlobalConfig.get_value(original_name)).to be_nil

      create(:installation_config, name: original_name, value: 'created')

      expect(GlobalConfig.get_value(original_name)).to eq('created')
      expect(GlobalConfig.get_value('UNRELATED')).to eq('keep')
      expect(redis).not_to have_received(:keys)
      expect(redis).not_to have_received(:scan)
    end

    it 'invalidates the current name on update and preserves unrelated cached values' do
      expect(GlobalConfig.get_value(config.name)).to eq('before')

      config.update!(value: 'after')

      expect(GlobalConfig.get_value(config.name)).to eq('after')
      expect(GlobalConfig.get_value('UNRELATED')).to eq('keep')
      expect(redis).not_to have_received(:keys)
      expect(redis).not_to have_received(:scan)
    end

    it 'invalidates the previous name and the cached missing destination on rename' do
      expect(GlobalConfig.get_value(config.name)).to eq('before')
      expect(GlobalConfig.get_value(renamed_name)).to be_nil

      config.update!(name: renamed_name)

      expect(GlobalConfig.get_value(original_name)).to be_nil
      expect(GlobalConfig.get_value(renamed_name)).to eq('before')
      expect(GlobalConfig.get_value('UNRELATED')).to eq('keep')
      expect(redis).not_to have_received(:keys)
      expect(redis).not_to have_received(:scan)
    end

    it 'invalidates the current name on destroy and preserves unrelated cached values' do
      expect(GlobalConfig.get_value(config.name)).to eq('before')

      config.destroy!

      expect(GlobalConfig.get_value(original_name)).to be_nil
      expect(GlobalConfig.get_value('UNRELATED')).to eq('keep')
      expect(redis).not_to have_received(:keys)
      expect(redis).not_to have_received(:scan)
    end

    it 'invalidates both the current and previous names when destroying a renamed record' do
      expect(GlobalConfig.get_value(config.name)).to eq('before')

      described_class.transaction do
        config.update!(name: renamed_name)
        expect(GlobalConfig.get_value(config.name)).to eq('before')
        config.destroy!
      end

      expect(GlobalConfig.get_value(original_name)).to be_nil
      expect(GlobalConfig.get_value(renamed_name)).to be_nil
      expect(GlobalConfig.get_value('UNRELATED')).to eq('keep')
      expect(redis).not_to have_received(:keys)
      expect(redis).not_to have_received(:scan)
    end

    it 'invalidates the persisted name when destroying a record with an unsaved rename' do
      expect(GlobalConfig.get_value(config.name)).to eq('before')
      config.reload
      config.name = renamed_name
      redis.set("#{prefix}:#{renamed_name}", { value: 'stale' }.to_json)

      config.destroy!

      expect(redis.get("#{prefix}:#{original_name}")).to be_nil
      expect(redis.get("#{prefix}:#{renamed_name}")).to be_nil
      expect(GlobalConfig.get_value('UNRELATED')).to eq('keep')
      expect(redis).not_to have_received(:keys)
      expect(redis).not_to have_received(:scan)
    end
  end
end
