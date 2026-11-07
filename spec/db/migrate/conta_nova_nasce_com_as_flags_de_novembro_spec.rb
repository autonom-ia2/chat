require 'rails_helper'
require Rails.root.join('db/migrate/20261108760000_conta_nova_nasce_com_as_flags_de_novembro.rb')

# #2667 — conta nova nasce com as 27 funções liberadas em 07/11/2026 e com a chave autonomia_agents_ao_receber_passagem
# em internal_attributes (Autonomia::AccountProvisioningDefaults). Só o padrão das contas novas
# (ACCOUNT_LEVEL_FEATURE_DEFAULTS) muda; as contas existentes não são tocadas. customer_base e
# instagram_assisted_onboarding ficam de fora e mantêm o padrão que já têm.
RSpec.describe ContaNovaNasceComAsFlagsDeNovembro do
  let(:features) { described_class::FEATURES }
  let(:fora) { %w[customer_base instagram_assisted_onboarding] }
  let(:colunas) { %w[feature_flags feature_flags_ext_1 feature_flags_ext_2 internal_attributes] }
  let(:passagem) { Autonomia::Agents::Operate::AoReceberPassagem::LIGADA_KEY }
  let(:config) { InstallationConfig.find_or_initialize_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS') }
  let(:validation_service) { instance_double(Account::SignUpEmailValidationService, perform: true) }

  around do |example|
    verbose = ActiveRecord::Migration.verbose
    ActiveRecord::Migration.verbose = false
    # O provisionamento do fork ligado, como em produção.
    with_modified_env(AUTONOMIA_ACCOUNT_DEFAULTS_ENABLED: 'true', AUTONOMIA_DEFAULT_ACCOUNT_USER_ID: '-1') { example.run }
  ensure
    ActiveRecord::Migration.verbose = verbose
  end

  # Como está em produção antes da migration: a lista do features.yml gravada com as 27 desligadas.
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

  # O caminho do cadastro (AccountBuilder), como em produção.
  def conta_pelo_cadastro
    allow(Account::SignUpEmailValidationService).to receive(:new).and_return(validation_service)
    AccountBuilder.new(account_name: 'Conta nova', email: "dona-#{SecureRandom.hex(4)}@example.com",
                       user_full_name: 'Dona', user_password: 'Senha-de-teste-1!', confirmed: true).perform.last.reload
  end

  it 'são 27, únicas, ligadas no features.yml, sem customer_base nem instagram', :aggregate_failures do
    expect(features.size).to eq(27)
    expect(features.uniq.size).to eq(27)
    yml = Featurable::FEATURE_LIST.select { |f| features.include?(f['name']) }
    expect(yml.size).to eq(27)
    expect(yml.pluck('enabled')).to all(be(true))
    expect(yml.pluck('column')).to all(be_in(%w[feature_flags_ext_1 feature_flags_ext_2]))
    expect(features & fora).to be_empty
    expect(Featurable::FEATURE_LIST.find { |f| f['name'] == 'customer_base' }['enabled']).to be(false)
  end

  it 'liga as 27 e preserva os outros padrões e campos', :aggregate_failures do
    antes = outros(padroes)
    instagram_antes = padrao_de('instagram_assisted_onboarding')
    expect(features.map { |feature| padrao_de(feature) }).to all(be(false))

    described_class.new.up

    expect(features.map { |feature| padrao_de(feature) }).to all(be(true))
    expect(outros(padroes)).to eq(antes)
    expect(padrao_de('customer_base')).to be(false)
    expect(padrao_de('instagram_assisted_onboarding')).to eq(instagram_antes)
  end

  it 'acrescenta a que faltar com os dados do features.yml', :aggregate_failures do
    config.value = config.value.reject { |f| f['name'] == 'seus_posts' }
    config.save!

    described_class.new.up

    item = padroes.find { |f| f['name'] == 'seus_posts' }
    yml = Featurable::FEATURE_LIST.find { |f| f['name'] == 'seus_posts' }
    expect(item.to_h).to eq(yml.merge('enabled' => true))
    expect(padroes.count { |f| f['name'] == 'seus_posts' }).to eq(1)
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

  it 'com valor que não é lista falha em vez de terminar sem ligar nada', :aggregate_failures do
    config.value = nil
    config.save!

    expect { described_class.new.up }.to raise_error(RuntimeError, /sem as flags ligadas: .*seus_posts/)
    expect(padroes).to be_nil
  end

  it 'falha e diz qual ficou desligada quando uma não liga' do
    allow(FeatureFlagRollout).to receive(:padrao!).and_call_original
    allow(FeatureFlagRollout).to receive(:padrao!).with('anuncios_login_unico', true)

    expect { described_class.new.up }.to raise_error(RuntimeError, 'ACCOUNT_LEVEL_FEATURE_DEFAULTS sem as flags ligadas: anuncios_login_unico')
  end

  it 'conta criada depois nasce com as 27 e a passagem, e a existente não muda', :aggregate_failures do
    existente = create(:account)
    existente.update_columns(internal_attributes: {}) # rubocop:disable Rails/SkipsModelValidations
    antes = existente.reload.attributes.slice(*colunas)
    expect(features.map { |feature| existente.feature_enabled?(feature) }).to all(be(false))

    described_class.new.up
    nova = create(:account).reload

    expect(existente.reload.attributes.slice(*colunas)).to eq(antes)
    features.each { |feature| expect(nova.feature_enabled?(feature)).to be(true), "#{feature} desligada na conta nova" }
    expect(nova.feature_enabled?('customer_base')).to be(false)
    expect(nova.internal_attributes[passagem]).to be(true)
  end

  it 'conta criada pelo cadastro nasce com as 27 e a passagem, sem a customer_base', :aggregate_failures do
    expect(features.map { |feature| conta_pelo_cadastro.feature_enabled?(feature) }).to all(be(false))

    described_class.new.up

    conta = conta_pelo_cadastro
    features.each { |feature| expect(conta.feature_enabled?(feature)).to be(true), "#{feature} desligada na conta nova" }
    expect(conta.feature_enabled?('customer_base')).to be(false)
    expect(conta.internal_attributes[passagem]).to be(true)
  end

  it 'a passagem dada por quem cria a conta continua' do
    conta = create(:account, internal_attributes: { passagem => false })

    expect(conta.reload.internal_attributes[passagem]).to be(false)
  end

  it 'down volta as 27 para desligado, preserva os outros e não desliga conta nenhuma', :aggregate_failures do
    antes = outros(padroes)
    described_class.new.up
    conta = create(:account)

    described_class.new.down

    expect(features.map { |feature| padrao_de(feature) }).to all(be(false))
    expect(outros(padroes)).to eq(antes)
    expect(features.map { |feature| conta.reload.feature_enabled?(feature) }).to all(be(true))
  end
end
