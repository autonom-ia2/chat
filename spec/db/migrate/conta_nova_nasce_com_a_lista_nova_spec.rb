require 'rails_helper'
require Rails.root.join('db/migrate/20261108560000_conta_nova_nasce_com_a_lista_nova.rb')

# #2253 — conta nova nasce com a lista de conversas nova (lista_quem_espera) no padrão das contas novas
# (ACCOUNT_LEVEL_FEATURE_DEFAULTS). As contas existentes não são tocadas.
RSpec.describe ContaNovaNasceComAListaNova do
  let(:feature) { described_class::FEATURE }
  let(:config) { InstallationConfig.find_or_initialize_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS') }

  around do |example|
    verbose = ActiveRecord::Migration.verbose
    ActiveRecord::Migration.verbose = false
    example.run
  ensure
    ActiveRecord::Migration.verbose = verbose
  end

  # Como está em produção antes da migration: a lista do features.yml gravada com ela desligada.
  before do
    config.value = Featurable::FEATURE_LIST.map do |item|
      item.merge('enabled' => item['name'] != feature && item['enabled'])
    end
    config.save!
    GlobalConfig.clear_cache
  end

  def padroes
    InstallationConfig.find_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS').value
  end

  def padrao
    padroes.find { |item| item['name'] == feature }['enabled']
  end

  def outros
    padroes.reject { |item| item['name'] == feature }.map(&:to_h)
  end

  it 'está na coluna ext_2, ligada no features.yml', :aggregate_failures do
    yml = Featurable::FEATURE_LIST.find { |item| item['name'] == feature }
    expect(yml['column']).to eq('feature_flags_ext_2')
    expect(yml['enabled']).to be(true)
  end

  it 'liga o padrão e preserva os outros', :aggregate_failures do
    antes = outros
    expect(padrao).to be(false)

    described_class.new.up

    expect(padrao).to be(true)
    expect(outros).to eq(antes)
  end

  it 'conta criada depois nasce com a lista nova e a existente não muda', :aggregate_failures do
    existente = create(:account)
    antes = existente.reload.attributes.slice('feature_flags', 'feature_flags_ext_1', 'feature_flags_ext_2')

    described_class.new.up
    nova = create(:account)

    expect(existente.reload.attributes.slice('feature_flags', 'feature_flags_ext_1', 'feature_flags_ext_2')).to eq(antes)
    expect(existente.feature_enabled?(feature)).to be(false)
    expect(nova.reload.feature_enabled?(feature)).to be(true)
  end

  it 'down volta o padrão e não desliga conta nenhuma', :aggregate_failures do
    antes = outros
    described_class.new.up
    conta = create(:account)

    described_class.new.down

    expect(padrao).to be(false)
    expect(outros).to eq(antes)
    expect(conta.reload.feature_enabled?(feature)).to be(true)
  end
end
