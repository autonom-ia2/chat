require 'rails_helper'
require Rails.root.join('db/migrate/20261108500000_conta_nova_nasce_com_a_agenda_do_contato.rb')

# #2221 — conta nova nasce com o contato na agenda do aparelho e a lida ao responder (#1865). Só o padrão das contas
# novas (ACCOUNT_LEVEL_FEATURE_DEFAULTS) muda; as contas existentes não são tocadas.
RSpec.describe ContaNovaNasceComAAgendaDoContato do
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

  it 'conta criada depois nasce com ela e a existente não muda', :aggregate_failures do
    existente = create(:account)
    antes = existente.reload.attributes.slice('feature_flags', 'feature_flags_ext_1')

    described_class.new.up

    expect(existente.reload.attributes.slice('feature_flags', 'feature_flags_ext_1')).to eq(antes)
    expect(existente.feature_enabled?(feature)).to be(false)
    expect(create(:account).feature_enabled?(feature)).to be(true)
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
