require 'rails_helper'
require Rails.root.join('db/migrate/20261108510000_conta_nova_nasce_com_o_agente_so_informa.rb')

# #2228 — conta nova nasce com a Fase 2 dos Agentes: o agente_so_informa no padrão das contas novas
# (ACCOUNT_LEVEL_FEATURE_DEFAULTS) e as chaves autonomia_agents_fase2 e autonomia_agente_ia_por_caixa em
# internal_attributes (Autonomia::AccountProvisioningDefaults). As contas existentes não são tocadas.
RSpec.describe ContaNovaNasceComOAgenteSoInforma do
  let(:feature) { described_class::FEATURE }
  let(:config) { InstallationConfig.find_or_initialize_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS') }
  let(:fase2) { Autonomia::Agents::Fase2 }
  let(:por_caixa) { Autonomia::Agents::AgenteIaPorCaixa }

  around do |example|
    verbose = ActiveRecord::Migration.verbose
    ActiveRecord::Migration.verbose = false
    # O provisionamento do fork ligado, como em produção.
    with_modified_env(AUTONOMIA_ACCOUNT_DEFAULTS_ENABLED: 'true', AUTONOMIA_DEFAULT_ACCOUNT_USER_ID: '-1') { example.run }
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

  it 'está na coluna ext_1, ligada no features.yml', :aggregate_failures do
    yml = Featurable::FEATURE_LIST.find { |item| item['name'] == feature }
    expect(yml['column']).to eq('feature_flags_ext_1')
    expect(yml['enabled']).to be(true)
  end

  it 'liga o padrão e preserva os outros', :aggregate_failures do
    antes = outros
    expect(padrao).to be(false)

    described_class.new.up

    expect(padrao).to be(true)
    expect(outros).to eq(antes)
  end

  it 'conta criada depois nasce com as três ligadas e a existente não muda', :aggregate_failures do
    existente = create(:account)
    existente.update_columns(internal_attributes: {}) # rubocop:disable Rails/SkipsModelValidations
    antes = existente.reload.attributes.slice('feature_flags', 'feature_flags_ext_1', 'internal_attributes')

    described_class.new.up
    nova = create(:account)

    expect(existente.reload.attributes.slice('feature_flags', 'feature_flags_ext_1', 'internal_attributes')).to eq(antes)
    expect(existente.feature_enabled?(feature)).to be(false)
    expect(fase2.ligada?(existente)).to be(false)
    expect(por_caixa.ligada?(existente)).to be(false)
    expect(nova.reload.feature_enabled?(feature)).to be(true)
    expect(fase2.ligada?(nova)).to be(true)
    expect(por_caixa.ligada?(nova)).to be(true)
  end

  it 'as chaves que já vêm na criação continuam', :aggregate_failures do
    conta = create(:account, internal_attributes: { 'signup_source' => 'shopify', fase2::INTERNAL_ATTR_KEY => false })

    expect(conta.reload.internal_attributes).to include('signup_source' => 'shopify', fase2::INTERNAL_ATTR_KEY => false,
                                                        por_caixa::INTERNAL_ATTR_KEY => true)
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
