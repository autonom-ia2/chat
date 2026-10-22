require 'rails_helper'
require Rails.root.join('db/migrate/20261108340000_conta_nova_nasce_com_ficar_com_a_conversa.rb')

# #2067 — conta nova nasce com "Ficar com a conversa ao enviar" (decisão do Rodrigo, 22/10/2026: ligada em todas as contas
# e na conta nova). Só o padrão das contas novas (ACCOUNT_LEVEL_FEATURE_DEFAULTS) muda; as contas existentes são ligadas
# pela Orquestração depois do deploy e não são tocadas aqui.
RSpec.describe ContaNovaNasceComFicarComAConversa do
  let(:features) { described_class::FEATURES }
  let(:config) { InstallationConfig.find_or_initialize_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS') }
  let(:validation_service) { instance_double(Account::SignUpEmailValidationService, perform: true) }

  around do |example|
    verbose = ActiveRecord::Migration.verbose
    ActiveRecord::Migration.verbose = false
    example.run
  ensure
    ActiveRecord::Migration.verbose = verbose
  end

  # Como está em produção antes da migration: a lista do features.yml gravada com a flag desligada.
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

  it 'é a ficar_com_a_conversa_ao_enviar, na coluna ext_1, ligada no features.yml', :aggregate_failures do
    expect(features).to contain_exactly('ficar_com_a_conversa_ao_enviar')
    yml = Featurable::FEATURE_LIST.select { |f| features.include?(f['name']) }
    expect(yml.size).to eq(1)
    expect(yml.pluck('column')).to all(eq('feature_flags_ext_1'))
    expect(yml.pluck('enabled')).to all(be(true))
  end

  it 'liga a flag e preserva os outros padrões e campos', :aggregate_failures do
    antes = outros(padroes)
    expect(features.map { |feature| padrao_de(feature) }).to all(be(false))

    described_class.new.up

    expect(features.map { |feature| padrao_de(feature) }).to all(be(true))
    expect(outros(padroes)).to eq(antes)
    expect(padroes.find { |f| f['name'] == 'ficar_com_a_conversa_ao_enviar' }['display_name']).to be_present
  end

  it 'acrescenta a que faltar com os dados do features.yml', :aggregate_failures do
    config.value = config.value.reject { |f| f['name'] == 'ficar_com_a_conversa_ao_enviar' }
    config.save!

    described_class.new.up

    item = padroes.find { |f| f['name'] == 'ficar_com_a_conversa_ao_enviar' }
    yml = Featurable::FEATURE_LIST.find { |f| f['name'] == 'ficar_com_a_conversa_ao_enviar' }
    expect(item.to_h).to eq(yml.merge('enabled' => true))
    expect(padroes.count { |f| f['name'] == 'ficar_com_a_conversa_ao_enviar' }).to eq(1)
  end

  it 'é idempotente' do
    described_class.new.up
    depois_da_primeira = padroes.map(&:to_h)

    described_class.new.up

    expect(padroes.map(&:to_h)).to eq(depois_da_primeira)
  end

  it 'conta criada depois nasce com a flag e a existente não muda', :aggregate_failures do
    existente = create(:account)
    antes = existente.reload.attributes.slice('feature_flags', 'feature_flags_ext_1')
    expect(features.map { |feature| existente.feature_enabled?(feature) }).to all(be(false))

    described_class.new.up

    expect(existente.reload.attributes.slice('feature_flags', 'feature_flags_ext_1')).to eq(antes)
    nova = create(:account)
    features.each { |feature| expect(nova.feature_enabled?(feature)).to be(true), "#{feature} desligada na conta nova" }
  end

  it 'conta criada pelo cadastro nasce com a flag' do
    expect(features.map { |feature| conta_pelo_cadastro.feature_enabled?(feature) }).to all(be(false))

    described_class.new.up

    conta = conta_pelo_cadastro
    features.each { |feature| expect(conta.feature_enabled?(feature)).to be(true), "#{feature} desligada na conta nova" }
  end

  it 'down volta a flag para desligado, preserva os outros e não desliga conta nenhuma', :aggregate_failures do
    antes = outros(padroes)
    described_class.new.up
    conta = create(:account)

    described_class.new.down

    expect(features.map { |feature| padrao_de(feature) }).to all(be(false))
    expect(outros(padroes)).to eq(antes)
    expect(features.map { |feature| conta.reload.feature_enabled?(feature) }).to all(be(true))
  end
end
