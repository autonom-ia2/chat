require 'rails_helper'
require Rails.root.join('db/migrate/20261025100000_conta_nova_nasce_com_as_flags_das_existentes.rb')

# #1175 — conta nova nasce com as funções que as existentes já têm. A conta é criada pelo caminho do cadastro
# (AccountBuilder, o do signup; o Super Admin cria direto pelo Account e passa pelo mesmo before_create) com o
# provisionamento do fork ligado, como em produção: o número fixo da coluna `feature_flags` não pode apagar o `companies`.
RSpec.describe ContaNovaNasceComAsFlagsDasExistentes do
  let(:features) { described_class::FEATURES }
  let(:config) { InstallationConfig.find_or_initialize_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS') }
  let(:validation_service) { instance_double(Account::SignUpEmailValidationService, perform: true) }

  around do |example|
    verbose = ActiveRecord::Migration.verbose
    ActiveRecord::Migration.verbose = false
    with_modified_env(AUTONOMIA_ACCOUNT_DEFAULTS_ENABLED: 'true', AUTONOMIA_DEFAULT_ACCOUNT_USER_ID: '-1') { example.run }
  ensure
    ActiveRecord::Migration.verbose = verbose
  end

  # Como está em produção antes da migration: a lista do features.yml gravada com as 10 desligadas.
  before do
    allow(Account::SignUpEmailValidationService).to receive(:new).and_return(validation_service)
    config.value = Featurable::FEATURE_LIST.map do |feature|
      { 'name' => feature['name'], 'enabled' => features.exclude?(feature['name']) && feature['enabled'] }
    end
    config.save!
    GlobalConfig.clear_cache
  end

  def conta_nova
    AccountBuilder.new(account_name: 'Conta nova', email: "dona-#{SecureRandom.hex(4)}@example.com",
                       user_full_name: 'Dona', user_password: 'Password123!', confirmed: true).perform.last.reload
  end

  def padrao_de(nome)
    InstallationConfig.find_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS').value.find { |f| f['name'] == nome }['enabled']
  end

  it 'conta criada pelo cadastro nasce com as 10 e a conversa aberta na campanha', :aggregate_failures do
    expect(features.map { |feature| conta_nova.feature_enabled?(feature) }).to all(be(false))

    described_class.new.up

    conta = conta_nova
    (features + ['campaign_open_window_text']).each do |feature|
      expect(conta.feature_enabled?(feature)).to be(true), "#{feature} desligada na conta nova"
    end
  end

  it 'mantém a base do número fixo e não liga as internas do Chatwoot', :aggregate_failures do
    described_class.new.up

    conta = conta_nova
    base = Autonomia::AccountProvisioningDefaults::DEFAULT_FEATURE_FLAGS
    companies = Account.flag_mapping['feature_flags'][:feature_companies]
    expect(conta.feature_flags).to eq(base | companies)
    expect(conta.feature_enabled?('contact_chatwoot_support_team')).to be(false)
  end

  it 'não mexe nas contas existentes', :aggregate_failures do
    conta = create(:account)
    antes = conta.reload.attributes.slice('feature_flags', 'feature_flags_ext_1')

    described_class.new.up

    expect(conta.reload.attributes.slice('feature_flags', 'feature_flags_ext_1')).to eq(antes)
  end

  it 'down volta só o padrão das contas novas', :aggregate_failures do
    described_class.new.up
    conta = conta_nova

    described_class.new.down

    expect(features.map { |feature| padrao_de(feature) }).to all(be(false))
    expect(features.map { |feature| conta.reload.feature_enabled?(feature) }).to all(be(true))
  end
end
