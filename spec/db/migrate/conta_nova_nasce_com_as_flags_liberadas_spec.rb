require 'rails_helper'
require Rails.root.join('db/migrate/20261108150000_conta_nova_nasce_com_as_flags_liberadas.rb')

# #1857 — conta nova nasce com as 14 funções liberadas em 19/10/2026. Só o padrão das contas novas
# (ACCOUNT_LEVEL_FEATURE_DEFAULTS) muda; as contas existentes não são tocadas. customer_base e
# instagram_assisted_onboarding ficam de fora e mantêm o padrão que já têm.
RSpec.describe ContaNovaNasceComAsFlagsLiberadas do
  let(:features) { described_class::FEATURES }
  let(:fora) { %w[customer_base instagram_assisted_onboarding] }
  let(:config) { InstallationConfig.find_or_initialize_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS') }
  let(:validation_service) { instance_double(Account::SignUpEmailValidationService, perform: true) }

  around do |example|
    verbose = ActiveRecord::Migration.verbose
    ActiveRecord::Migration.verbose = false
    example.run
  ensure
    ActiveRecord::Migration.verbose = verbose
  end

  # Como está em produção antes da migration: a lista do features.yml gravada com as 14 desligadas.
  before do
    config.value = Featurable::FEATURE_LIST.map do |feature|
      feature.merge('enabled' => features.exclude?(feature['name']) && feature['enabled'])
    end
    config.save!
    GlobalConfig.clear_cache
  end

  def padroes
    InstallationConfig.find_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS').value
  end

  def padrao_de(nome)
    padroes.find { |f| f['name'] == nome }['enabled']
  end

  def outros(lista)
    lista.reject { |f| features.include?(f['name']) }.map(&:to_h)
  end

  # O caminho do cadastro (AccountBuilder), com o provisionamento do fork ligado, como em produção.
  def conta_pelo_cadastro
    allow(Account::SignUpEmailValidationService).to receive(:new).and_return(validation_service)
    with_modified_env(AUTONOMIA_ACCOUNT_DEFAULTS_ENABLED: 'true', AUTONOMIA_DEFAULT_ACCOUNT_USER_ID: '-1') do
      AccountBuilder.new(account_name: 'Conta nova', email: "dona-#{SecureRandom.hex(4)}@example.com",
                         user_full_name: 'Dona', user_password: 'Senha-de-teste-1!', confirmed: true).perform.last.reload
    end
  end

  it 'são 14, na coluna ext_1, ligadas no features.yml, sem customer_base nem instagram', :aggregate_failures do
    expect(features.size).to eq(14)
    yml = Featurable::FEATURE_LIST.select { |f| features.include?(f['name']) }
    expect(yml.size).to eq(14)
    expect(yml.pluck('column')).to all(eq('feature_flags_ext_1'))
    expect(yml.pluck('enabled')).to all(be(true))
    expect(features & fora).to be_empty
    expect(Featurable::FEATURE_LIST.find { |f| f['name'] == 'customer_base' }['enabled']).to be(false)
  end

  it 'liga as 14 e preserva os outros padrões e campos', :aggregate_failures do
    antes = outros(padroes)
    instagram_antes = padrao_de('instagram_assisted_onboarding')
    expect(features.map { |feature| padrao_de(feature) }).to all(be(false))

    described_class.new.up

    expect(features.map { |feature| padrao_de(feature) }).to all(be(true))
    expect(outros(padroes)).to eq(antes)
    expect(padrao_de('customer_base')).to be(false)
    expect(padrao_de('instagram_assisted_onboarding')).to eq(instagram_antes)
    expect(padroes.find { |f| f['name'] == 'memoria_ia' }['display_name']).to be_present
  end

  it 'acrescenta a que faltar com os dados do features.yml', :aggregate_failures do
    config.value = config.value.reject { |f| f['name'] == 'memoria_ia' }
    config.save!

    described_class.new.up

    item = padroes.find { |f| f['name'] == 'memoria_ia' }
    yml = Featurable::FEATURE_LIST.find { |f| f['name'] == 'memoria_ia' }
    expect(item.to_h).to eq(yml.merge('enabled' => true))
    expect(padroes.count { |f| f['name'] == 'memoria_ia' }).to eq(1)
  end

  it 'é idempotente' do
    described_class.new.up
    depois_da_primeira = padroes.map(&:to_h)

    described_class.new.up

    expect(padroes.map(&:to_h)).to eq(depois_da_primeira)
  end

  it 'sem a configuração gravada não faz nada' do
    config.destroy!

    described_class.new.up

    expect(InstallationConfig.find_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS')).to be_nil
  end

  it 'com valor que não é lista não regrava nada' do
    config.value = nil
    config.save!

    described_class.new.up

    expect(padroes).to be_nil
  end

  it 'conta criada depois nasce com as 14 e a existente não muda', :aggregate_failures do
    existente = create(:account)
    antes = existente.reload.attributes.slice('feature_flags', 'feature_flags_ext_1')
    expect(features.map { |feature| existente.feature_enabled?(feature) }).to all(be(false))

    described_class.new.up

    expect(existente.reload.attributes.slice('feature_flags', 'feature_flags_ext_1')).to eq(antes)
    nova = create(:account)
    features.each { |feature| expect(nova.feature_enabled?(feature)).to be(true), "#{feature} desligada na conta nova" }
    expect(nova.feature_enabled?('customer_base')).to be(false)
  end

  it 'conta criada pelo cadastro nasce com as 14, sem a customer_base', :aggregate_failures do
    expect(features.map { |feature| conta_pelo_cadastro.feature_enabled?(feature) }).to all(be(false))

    described_class.new.up

    conta = conta_pelo_cadastro
    features.each { |feature| expect(conta.feature_enabled?(feature)).to be(true), "#{feature} desligada na conta nova" }
    expect(conta.feature_enabled?('customer_base')).to be(false)
  end

  it 'down volta as 14 para desligado, preserva os outros e não desliga conta nenhuma', :aggregate_failures do
    antes = outros(padroes)
    described_class.new.up
    conta = create(:account)

    described_class.new.down

    expect(features.map { |feature| padrao_de(feature) }).to all(be(false))
    expect(outros(padroes)).to eq(antes)
    expect(padrao_de('instagram_assisted_onboarding')).to be(true)
    expect(features.map { |feature| conta.reload.feature_enabled?(feature) }).to all(be(true))
  end
end
