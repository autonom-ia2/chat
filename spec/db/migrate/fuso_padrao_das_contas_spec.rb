require 'rails_helper'
require Rails.root.join('db/migrate/20261004230000_fuso_padrao_das_contas.rb')

# Fuso de São Paulo só onde a conta não tem nenhum; o fuso escolhido fica; rodar duas vezes dá o mesmo.
RSpec.describe FusoPadraoDasContas do
  around do |example|
    verbose = ActiveRecord::Migration.verbose
    ActiveRecord::Migration.verbose = false
    example.run
  ensure
    ActiveRecord::Migration.verbose = verbose
  end

  def conta(custom: {}, settings: {})
    create(:account).tap { |registro| registro.update_columns(custom_attributes: custom, settings: settings) } # rubocop:disable Rails/SkipsModelValidations
  end

  it 'preenche os dois fusos vazios e preserva o que a corretora escolheu', :aggregate_failures do
    vazia = conta(custom: { 'onboarding_step' => 'done' })
    escolhida = conta(custom: { 'timezone' => 'America/Manaus' }, settings: { 'reporting_timezone' => 'America/Manaus' })

    2.times { described_class.new.up }

    expect(vazia.reload.custom_attributes).to eq('onboarding_step' => 'done', 'timezone' => 'America/Sao_Paulo')
    expect(vazia.reporting_timezone).to eq('America/Sao_Paulo')
    expect(escolhida.reload.custom_attributes['timezone']).to eq('America/Manaus')
    expect(escolhida.reporting_timezone).to eq('America/Manaus')
  end
end
