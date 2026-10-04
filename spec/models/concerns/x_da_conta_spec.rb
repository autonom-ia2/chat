require 'rails_helper'

# `x-da-conta` diz ao Guia de que modelo é o id. Nome que não resolve faria a conferência
# pular aquele id em silêncio (Formatos::PorDentro#fora_da_conta), então todo nome tem de existir.
RSpec.describe 'x-da-conta nos esquemas' do # rubocop:disable RSpec/DescribeClass
  def modelos(trecho)
    case trecho
    when Hash then [trecho.dig('x-da-conta', 'modelo')].compact + trecho.values.flat_map { |filho| modelos(filho) }
    when Array then trecho.flat_map { |filho| modelos(filho) }
    else []
    end
  end

  it 'todo modelo citado existe', :aggregate_failures do
    regra = AutomationRule.new(account: create(:account))
    esquemas = [AutomationRuleSchema.actions(regra), AutomationRuleSchema.conditions(regra), MacroSchema.actions,
                Crm::StageAutomationStepSchema.action_config]
    nomes = esquemas.flat_map { |esquema| modelos(esquema) }.uniq

    expect(nomes).not_to be_empty
    nomes.each { |nome| expect(nome.safe_constantize).to be_present, "x-da-conta aponta para #{nome}, que não existe" }
  end
end
