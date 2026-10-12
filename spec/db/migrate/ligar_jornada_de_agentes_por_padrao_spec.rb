require 'rails_helper'
require Rails.root.join('db/migrate/20261022100000_ligar_jornada_de_agentes_por_padrao.rb')

# #1181 — a jornada nova de Agentes vira padrão: contas novas nascem com ela (ACCOUNT_LEVEL_FEATURE_DEFAULTS) e toda
# conta existente sem ela ganha. O down volta só o padrão.
RSpec.describe LigarJornadaDeAgentesPorPadrao do
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
      { 'name' => 'crm', 'enabled' => false },
      { 'name' => 'inbound_emails', 'enabled' => true }
    ]
    config.save!
  end

  def padrao_de(nome)
    InstallationConfig.find_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS').value.find { |f| f['name'] == nome }['enabled']
  end

  it 'liga o padrão das contas novas e não mexe nas outras opções', :aggregate_failures do
    described_class.new.up

    expect(padrao_de(feature)).to be(true)
    expect(padrao_de('crm')).to be(false)
    expect(padrao_de('inbound_emails')).to be(true)
  end

  it 'liga a jornada em toda conta que ainda não tem, sem desligar nada', :aggregate_failures do
    sem = create(:account)
    sem.disable_features!(feature)
    com = create(:account)
    com.enable_features!(feature, 'crm')

    described_class.new.up

    expect(sem.reload.feature_enabled?(feature)).to be(true)
    expect(com.reload.feature_enabled?(feature)).to be(true)
    expect(com.feature_enabled?('crm')).to be(true)
  end

  it 'conta antiga com dado inválido não derruba a migration e é ligada', :aggregate_failures do
    invalida = create(:account)
    invalida.disable_features!(feature)
    invalida.update_columns(name: '') # rubocop:disable Rails/SkipsModelValidations
    expect(invalida.reload).not_to be_valid

    expect { described_class.new.up }.not_to raise_error
    expect(invalida.reload.feature_enabled?(feature)).to be(true)
    expect(invalida.name).to eq('')
  end

  it 'conta criada depois nasce com a jornada' do
    described_class.new.up

    expect(create(:account).feature_enabled?(feature)).to be(true)
  end

  it 'rodar duas vezes dá o mesmo resultado', :aggregate_failures do
    conta = create(:account)
    2.times { described_class.new.up }

    expect(padrao_de(feature)).to be(true)
    expect(conta.reload.feature_enabled?(feature)).to be(true)
  end

  it 'acrescenta o item da jornada quando ele não está no padrão', :aggregate_failures do
    config.value = [{ 'name' => 'crm', 'enabled' => false }]
    config.save!

    described_class.new.up

    expect(padrao_de(feature)).to be(true)
    expect(padrao_de('crm')).to be(false)
  end

  it 'down volta só o padrão das contas novas', :aggregate_failures do
    conta = create(:account)
    described_class.new.up

    described_class.new.down

    expect(padrao_de(feature)).to be(false)
    expect(conta.reload.feature_enabled?(feature)).to be(true)
  end
end
