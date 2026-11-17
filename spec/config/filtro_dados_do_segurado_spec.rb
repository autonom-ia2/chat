require 'rails_helper'

# #3043 — os dados do segurado para a cotação da renovação chegam no PATCH do seguro e no POST da apólice nova: nenhum
# deles vai para a linha de parâmetros do log.
# rubocop:disable RSpec/DescribeClass -- é a configuração do filtro do log, não uma classe (mesmo padrão de spec/config)
describe 'Filtro do log: dados do segurado da carteira' do
  it 'nascimento, sexo, CEP, placa e classe de bônus saem filtrados' do
    filtro = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    pedido = { 'nascimento' => '1985-03-15', 'sexo' => 'F', 'cep' => '12345678', 'placa' => 'EXM0A00', 'bonus' => 5, 'tipo' => 'auto' }

    expect(filtro.filter(pedido)).to eq(
      'nascimento' => '[FILTERED]', 'sexo' => '[FILTERED]', 'cep' => '[FILTERED]', 'placa' => '[FILTERED]', 'bonus' => '[FILTERED]',
      'tipo' => 'auto'
    )
  end

  it 'o CEP sai só pela chave exata: accepted e exception continuam no log' do
    filtro = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)

    expect(filtro.filter('accepted' => 'true', 'exception' => 'x')).to eq('accepted' => 'true', 'exception' => 'x')
  end
end
# rubocop:enable RSpec/DescribeClass
