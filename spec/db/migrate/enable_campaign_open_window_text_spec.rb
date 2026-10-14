require 'rails_helper'
require Rails.root.join('db/migrate/20261024100001_enable_campaign_open_window_text.rb')

# #1335 — a conversa aberta na campanha liga em toda conta existente e as contas novas nascem com ela
# (ACCOUNT_LEVEL_FEATURE_DEFAULTS). O helper comum (lib/feature_flag_rollout.rb) é coberto no spec do #1398;
# aqui só o efeito para campaign_open_window_text.
RSpec.describe EnableCampaignOpenWindowText do
  let(:feature) { described_class::FEATURE }
  let(:config) { InstallationConfig.find_or_initialize_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS') }

  around do |example|
    verbose = ActiveRecord::Migration.verbose
    ActiveRecord::Migration.verbose = false
    example.run
  ensure
    ActiveRecord::Migration.verbose = verbose
  end

  before do
    config.value = [
      { 'name' => feature, 'enabled' => false },
      { 'name' => 'crm', 'enabled' => false }
    ]
    config.save!
  end

  def padrao_de(nome)
    InstallationConfig.find_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS').value.find { |f| f['name'] == nome }['enabled']
  end

  it 'conta existente sem a conversa aberta passa a ter, sem mexer nas outras flags', :aggregate_failures do
    conta = create(:account)
    conta.disable_features!(feature)
    conta.enable_features!('crm')
    outras = conta.reload.feature_flags_ext_1

    described_class.new.up

    expect(conta.reload.feature_enabled?(feature)).to be(true)
    expect(conta.feature_flags_ext_1).to eq(outras | Account.flag_mapping['feature_flags_ext_1'][:feature_campaign_open_window_text])
    expect(conta.feature_enabled?('crm')).to be(true)
  end

  it 'conta criada depois nasce com a conversa aberta', :aggregate_failures do
    expect(create(:account).feature_enabled?(feature)).to be(false)

    described_class.new.up

    expect(padrao_de(feature)).to be(true)
    expect(padrao_de('crm')).to be(false)
    expect(create(:account).feature_enabled?(feature)).to be(true)
  end

  it 'down volta só o padrão das contas novas e não desliga conta nenhuma', :aggregate_failures do
    conta = create(:account)
    described_class.new.up

    described_class.new.down

    expect(padrao_de(feature)).to be(false)
    expect(conta.reload.feature_enabled?(feature)).to be(true)
  end
end
