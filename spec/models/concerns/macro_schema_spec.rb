require 'rails_helper'

RSpec.describe MacroSchema do
  let(:conta) { create(:account) }

  def erros(acoes)
    macro = Macro.new(account: conta, name: 'M', actions: acoes)
    macro.validate
    macro.errors.full_messages.join(' | ')
  end

  # AC-G3: a macro executa pelo Macros::ExecutionService, que herda as ações do ActionService.
  it 'toda ação da macro tem ramo, e todo ramo é um método do executor', :aggregate_failures do
    ramos = described_class.actions['items']['allOf'].map { |ramo| ramo.dig('if', 'properties', 'action_name', 'const') }

    expect(ramos).to match_array(Macro::ACTIONS_ATTRS)
    ramos.each do |nome|
      expect(Macros::ExecutionService.private_method_defined?(nome) || Macros::ExecutionService.method_defined?(nome))
        .to be(true), "#{nome} não é método do executor"
    end
  end

  it 'não marca nada como sem volta: criar a macro não manda nada' do
    expect(described_class.actions['items']['allOf'].none? { |ramo| ramo['x-sem-volta'] }).to be(true)
  end

  it 'aceita self em assign_agent e recusa o que o executor não lê', :aggregate_failures do
    expect(erros([{ action_name: 'assign_agent', action_params: ['self'] }, { action_name: 'add_label', action_params: ['vip'] }])).to eq('')
    expect(erros([{ action_name: 'crm_create_card', action_params: [1] }])).to include('"crm_create_card" is not one of')
    expect(erros([{ action_name: 'assign_team', action_params: ['3'] }])).to include('must be of type integer')
  end
end
