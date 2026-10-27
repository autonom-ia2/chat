# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Featurable do
  it 'appends assisted Instagram onboarding enabled by default without changing previous bit positions' do
    index = described_class::FEATURE_LIST.index { |item| item['name'] == 'instagram_assisted_onboarding' }
    feature = described_class::FEATURE_LIST[index]
    expect(feature).to include('name' => 'instagram_assisted_onboarding', 'enabled' => true, 'column' => 'feature_flags_ext_1')
    previous = described_class.feature_flag_mappings_for(described_class::FEATURE_LIST[0...index])
    expect(described_class::FEATURES_BY_COLUMN['feature_flags']).to eq(previous['feature_flags'])
    expect(described_class::FEATURES_BY_COLUMN['feature_flags_ext_1'].slice(*previous['feature_flags_ext_1'].keys))
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

    it 'maps flags of feature_flags_ext_2 with their own bit positions (#2186)' do
      mappings = described_class.feature_flag_mappings_for([
                                                             { 'name' => 'base_one' },
                                                             { 'name' => 'ext_one', 'column' => 'feature_flags_ext_1' },
                                                             { 'name' => 'ext2_one', 'column' => 'feature_flags_ext_2' },
                                                             { 'name' => 'ext2_two', 'column' => 'feature_flags_ext_2' }
                                                           ])

      expect(mappings['feature_flags']).to eq(1 => :feature_base_one)
      expect(mappings['feature_flags_ext_1']).to eq(1 => :feature_ext_one)
      expect(mappings['feature_flags_ext_2']).to eq(1 => :feature_ext2_one, 2 => :feature_ext2_two)
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

  # #2186: uma flag declarada com `column: feature_flags_ext_2` liga, desliga, é lida e não toca nas outras colunas.
  # Lista de teste, sem flag nova no features.yml: um model sobre a tabela accounts com o mesmo mapa por coluna.
  describe 'feature_flags_ext_2' do
    let(:test_features) do
      [
        { 'name' => 'base_one' },
        { 'name' => 'ext1_one', 'column' => 'feature_flags_ext_1' },
        { 'name' => 'ext2_one', 'column' => 'feature_flags_ext_2' },
        { 'name' => 'ext2_two', 'column' => 'feature_flags_ext_2' }
      ]
    end
    let(:model) do
      mappings = described_class.feature_flag_mappings_for(test_features)
      stub_const('FeaturableExt2Conta', Class.new(ApplicationRecord) do
        self.table_name = 'accounts'
        include FlagShihTzu

        Featurable::FEATURE_FLAG_COLUMNS.each do |column|
          has_flags mappings.fetch(column).merge(column: column).merge(Featurable::QUERY_MODE)
        end
      end)
    end
    let(:conta) { model.find(create(:account).id) }

    it 'adds the column to the accounts table with default 0 and to the account flag columns' do
      column = Account.columns_hash['feature_flags_ext_2']

      expect(column.sql_type).to eq('bigint')
      expect(column.default).to eq('0')
      expect(column.null).to be(false)
      expect(create(:account).feature_flags_ext_2).to eq(0)
      expect(Account.flag_columns).to include('feature_flags_ext_2')
      bits_do_features_yml = described_class::FEATURES_BY_COLUMN['feature_flags_ext_2'].to_h { |posicao, nome| [nome, 1 << (posicao - 1)] }
      expect(Account.flag_mapping['feature_flags_ext_2']).to eq(bits_do_features_yml)
    end

    it 'turns a flag on in feature_flags_ext_2 only and reads it back from the database' do
      outras = conta.attributes.slice('feature_flags', 'feature_flags_ext_1')

      conta.update!(feature_ext2_two: true)
      conta.reload

      expect(conta.feature_ext2_two?).to be(true)
      expect(conta.feature_ext2_one?).to be(false)
      expect(conta.feature_flags_ext_2).to eq(2)
      expect(conta.attributes.slice('feature_flags', 'feature_flags_ext_1')).to eq(outras)
      expect(model.feature_ext2_two.pluck(:id)).to eq([conta.id])
    end

    it 'turns a flag off in feature_flags_ext_2 without touching the other columns' do
      conta.update!(feature_ext2_two: true)
      outras = conta.reload.attributes.slice('feature_flags', 'feature_flags_ext_1')

      conta.update!(feature_ext2_two: false)

      expect(conta.reload.feature_ext2_two?).to be(false)
      expect(conta.feature_flags_ext_2).to eq(0)
      expect(conta.attributes.slice('feature_flags', 'feature_flags_ext_1')).to eq(outras)
      expect(model.feature_ext2_two.pluck(:id)).to be_empty
    end

    # #2084: a primeira flag da ext_2 (contato_relacao) entra na lista de todas; ligar uma da ext_1 não toca na ext_2.
    context 'with the real Account' do
      let(:account) { create(:account) }
      let(:flags_das_outras_colunas) do
        described_class::FEATURES_BY_COLUMN.slice('feature_flags', 'feature_flags_ext_1').values.flat_map(&:values)
      end
      let(:flags_da_ext_2) { described_class::FEATURES_BY_COLUMN['feature_flags_ext_2'].values }

      it 'lists the feature_flags_ext_2 flags among all, and selects only the ext_1 one that was turned on' do
        account.enable_features!('data_import')

        expect(flags_da_ext_2).to include(:feature_contato_relacao)
        expect(account.all_feature_flags).to match_array(flags_das_outras_colunas + flags_da_ext_2)
        expect(account.reload.selected_feature_flags).to include(:feature_data_import)
        expect(account.selected_feature_flags - flags_das_outras_colunas).to be_empty
        expect(account.feature_flags_ext_2).to eq(0)
      end

      it 'sets selected_feature_flags (the Super Admin path) with ext_1 flags without touching feature_flags_ext_2' do
        # O primeiro bit da ext_2 que ainda não tem flag: cada flag nova ocupa o próximo (#2202 tomou o valor 4).
        bit_sem_flag = 1 << described_class::FEATURES_BY_COLUMN['feature_flags_ext_2'].keys.max
        account.update_columns(feature_flags_ext_2: bit_sem_flag) # rubocop:disable Rails/SkipsModelValidations
        account.reload

        account.selected_feature_flags = [:feature_data_import, :feature_audit_log_ip_address]
        account.save!
        account.reload

        expect(account.selected_feature_flags).to contain_exactly(:feature_data_import, :feature_audit_log_ip_address)
        expect(account.feature_flags_ext_2).to eq(bit_sem_flag)
      end
    end

    it 'keeps the same bit position in another column isolated from feature_flags_ext_2' do
      conta.update_columns(feature_flags_ext_1: 0, feature_flags_ext_2: 0) # rubocop:disable Rails/SkipsModelValidations
      conta.update!(feature_ext1_one: true)

      expect(conta.reload.feature_ext1_one?).to be(true)
      expect(conta.feature_ext2_one?).to be(false)
      expect(conta.feature_flags_ext_2).to eq(0)

      conta.update!(feature_ext2_one: true, feature_ext1_one: false)

      expect(conta.reload.feature_ext2_one?).to be(true)
      expect(conta.feature_ext1_one?).to be(false)
      expect(conta.feature_flags_ext_1).to eq(0)
    end
  end
end
