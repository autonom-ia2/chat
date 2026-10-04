# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Featurable do
  it 'appends assisted Instagram onboarding enabled by default without changing previous bit positions' do
    feature = described_class::FEATURE_LIST.last
    expect(feature).to include('name' => 'instagram_assisted_onboarding', 'enabled' => true, 'column' => 'feature_flags_ext_1')
    previous = described_class.feature_flag_mappings_for(described_class::FEATURE_LIST[0...-1])
    expect(described_class::FEATURES_BY_COLUMN['feature_flags']).to eq(previous['feature_flags'])
    expect(described_class::FEATURES_BY_COLUMN['feature_flags_ext_1'].except(previous['feature_flags_ext_1'].size + 1))
      .to eq(previous['feature_flags_ext_1'])
  end

  it 'enables the feature on new accounts through account defaults without enabling the Instagram channel' do
    defaults = described_class::FEATURE_LIST.map do |feature|
      feature['name'] == 'channel_instagram' ? feature.merge('enabled' => false) : feature
    end
    InstallationConfig.find_or_initialize_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS').update!(value: defaults)
    account = create(:account)
    expect(account.feature_enabled?('instagram_assisted_onboarding')).to be true
    expect(account.feature_enabled?('channel_instagram')).to be false
  end

  it 'adds the ON default through normal ConfigLoader sync without rewriting existing account bits' do
    defaults = described_class::FEATURE_LIST.reject { |feature| feature['name'] == 'instagram_assisted_onboarding' }
    InstallationConfig.find_or_initialize_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS').update!(value: defaults)
    existing = create(:account)
    previous_bits = existing.attributes.slice('feature_flags', 'feature_flags_ext_1')

    ConfigLoader.new.process

    expect(create(:account).feature_enabled?('instagram_assisted_onboarding')).to be true
    expect(existing.reload.attributes.slice('feature_flags', 'feature_flags_ext_1')).to eq(previous_bits)
    expect(existing.feature_enabled?('instagram_assisted_onboarding')).to be false
  end

  describe '.feature_flag_mappings_for' do
    it 'maps features to the default feature_flags column when column is omitted' do
      mappings = described_class.feature_flag_mappings_for([
                                                             { 'name' => 'inbound_emails' },
                                                             { 'name' => 'ip_lookup' }
                                                           ])

      expect(mappings['feature_flags']).to eq(
        1 => :feature_inbound_emails,
        2 => :feature_ip_lookup
      )
      expect(mappings['feature_flags_ext_1']).to eq({})
    end

    it 'maps extension flags to feature_flags_ext_1 with independent bit positions' do
      mappings = described_class.feature_flag_mappings_for([
                                                             { 'name' => 'inbound_emails' },
                                                             { 'name' => 'ext_one', 'column' => 'feature_flags_ext_1' },
                                                             { 'name' => 'ext_two', 'column' => 'feature_flags_ext_1' }
                                                           ])

      expect(mappings['feature_flags']).to eq(1 => :feature_inbound_emails)
      expect(mappings['feature_flags_ext_1']).to eq(
        1 => :feature_ext_one,
        2 => :feature_ext_two
      )
    end

    it 'raises when a feature references an unknown flag column' do
      expect do
        described_class.feature_flag_mappings_for([
                                                    { 'name' => 'unknown_column_feature', 'column' => 'feature_flags_3' }
                                                  ])
      end.to raise_error(ArgumentError, /Unknown account feature flag column: feature_flags_3/)
    end

    it 'raises when a flag column has more than the supported number of features' do
      features = Array.new(64) { |index| { 'name' => "feature_#{index}" } }

      expect do
        described_class.feature_flag_mappings_for(features)
      end.to raise_error(ArgumentError, /feature_flags supports up to 63 features/)
    end
  end
end
