require 'rails_helper'

# Passo `perguntar_ao_decisor` (#858): a recusa diz o que está errado e o que é aceito, para ensinar o Guia.
RSpec.describe AutomationRule do
  let(:account) { create(:account) }
  let(:decisor) { create(:autonomia_decisor, account: account) }

  def regra(action_params)
    build(:automation_rule, account: account, event_name: 'message_created',
                            conditions: [{ attribute_key: 'message_type', filter_operator: 'equal_to', values: ['incoming'], query_operator: nil }],
                            actions: [{ action_name: 'perguntar_ao_decisor', action_params: action_params },
                                      { action_name: 'add_label', action_params: ['lead'] }])
  end

  it 'aceita o Decisor da conta com uma das respostas dele' do
    expect(regra([decisor.id, 'sim'])).to be_valid
    expect(regra([decisor.id.to_s, 'nao'])).to be_valid
  end

  it 'recusa Decisor de outra conta' do
    de_outra = create(:autonomia_decisor)
    rule = regra([de_outra.id, 'sim'])

    expect(rule).not_to be_valid
    expect(rule.errors[:actions].join).to include('not found in this account', '[decisor_id, answer_that_continues]')
  end

  it 'recusa chave que o Decisor não tem, listando as que ele tem' do
    rule = regra([decisor.id, 'talvez'])

    expect(rule).not_to be_valid
    expect(rule.errors[:actions].join).to include("'talvez'", 'sim, nao')
  end

  it 'lista as ações aceitas quando a ação não existe' do
    rule = build(:automation_rule, account: account, actions: [{ action_name: 'decidir_tudo', action_params: [] }])

    expect(rule).not_to be_valid
    expect(rule.errors[:actions].join).to include('decidir_tudo', 'Supported actions:', 'perguntar_ao_decisor', 'crm_create_card')
  end
end
