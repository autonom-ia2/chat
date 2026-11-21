require 'rails_helper'
require Rails.root.join('db/migrate/20261120100000_ligar_automacao_passos_novos_em_todas.rb')

# #2414 (Refs #2982) — os 6 passos novos da Automação livre ficam ligados para todo mundo: contas novas nascem com eles e
# toda conta existente sem eles ganha. O backup de cada conta ligada vai ao log (id e valor de feature_flags_ext_2 antes), e o down desliga
# a flag SÓ nas contas que o up ligou: quem já tinha continua com ela.
RSpec.describe LigarAutomacaoPassosNovosEmTodas do
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
    config.value = [{ 'name' => feature, 'enabled' => false }, { 'name' => 'crm', 'enabled' => false }]
    config.save!
    GlobalConfig.clear_cache
  end

  def padrao_de(nome)
    InstallationConfig.find_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS').value.find { |f| f['name'] == nome }['enabled']
  end

  def registro
    InstallationConfig.find_by(name: described_class::REGISTRO)&.value
  end

  def conta(com_a_flag:)
    create(:account).tap do |account|
      com_a_flag ? account.enable_features!(feature) : account.disable_features!(feature)
    end
  end

  it 'a entrada do features.yml fica ligada, no mesmo bit' do
    item = Featurable::FEATURE_LIST.find { |f| f['name'] == feature }

    expect(item.values_at('enabled', 'column')).to eq([true, 'feature_flags_ext_2'])
    expect(Account.flag_mapping['feature_flags_ext_2'][:"feature_#{feature}"]).to eq(1 << 46)
  end

  it 'liga o padrão das contas novas e não mexe nas outras opções', :aggregate_failures do
    described_class.new.up

    expect(padrao_de(feature)).to be(true)
    expect(padrao_de('crm')).to be(false)
    expect(create(:account).feature_enabled?(feature)).to be(true)
  end

  it 'liga em toda conta que ainda não tem, sem desligar nada, e guarda só as que ligou', :aggregate_failures do
    sem = conta(com_a_flag: false)
    com = conta(com_a_flag: true)
    com.enable_features!('crm')

    described_class.new.up

    expect([sem.reload, com.reload].map { |account| account.feature_enabled?(feature) }).to eq([true, true])
    expect(com.feature_enabled?('crm')).to be(true)
    expect(registro).to eq([sem.id])
  end

  it 'leva ao log o backup de cada conta ligada: o id e o valor de feature_flags_ext_2 antes' do
    sem = conta(com_a_flag: false)
    antes = sem.reload.feature_flags_ext_2
    allow(Rails.logger).to receive(:info).and_call_original

    described_class.new.up

    expect(Rails.logger).to have_received(:info)
      .with("[#{described_class::LOG_TAG}] conta=#{sem.id} ligada feature_flags_ext_2_antes=#{antes}")
  end

  it 'conta antiga com dado inválido não derruba a migration e é ligada', :aggregate_failures do
    invalida = conta(com_a_flag: false)
    invalida.update_columns(name: '') # rubocop:disable Rails/SkipsModelValidations
    expect(invalida.reload).not_to be_valid

    expect { described_class.new.up }.not_to raise_error
    expect(invalida.reload.feature_enabled?(feature)).to be(true)
  end

  it 'rodar duas vezes não perde as contas que a primeira ligou' do
    primeira = conta(com_a_flag: false)
    described_class.new.up
    segunda = conta(com_a_flag: false)

    described_class.new.up

    expect(registro).to contain_exactly(primeira.id, segunda.id)
  end

  it 'down desliga só as contas que o up ligou, volta o padrão e apaga o registro', :aggregate_failures do
    sem = conta(com_a_flag: false)
    com = conta(com_a_flag: true)
    described_class.new.up

    described_class.new.down

    expect(sem.reload.feature_enabled?(feature)).to be(false)
    expect(com.reload.feature_enabled?(feature)).to be(true)
    expect(padrao_de(feature)).to be(false)
    expect(registro).to be_nil
  end

  it 'down sem o registro não desliga conta nenhuma' do
    sem = conta(com_a_flag: false)
    described_class.new.up
    InstallationConfig.find_by(name: described_class::REGISTRO).destroy!

    described_class.new.down

    expect(sem.reload.feature_enabled?(feature)).to be(true)
  end
end
