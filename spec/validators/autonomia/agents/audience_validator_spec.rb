require 'rails_helper'

# #284 (Entrega 2a) — a árvore de público-alvo é validada no model do agente.
RSpec.describe Autonomia::Agents::AudienceValidator do
  let(:account) { create(:account) }

  def agent_with(config)
    Autonomia::Agents::Agent.new(account: account, name: 'Ana', agent_type: 'custom', instruction: 'Atenda.', config: config)
  end

  def leaf(attribute_key, filter_operator, values = nil)
    { 'attribute_key' => attribute_key, 'filter_operator' => filter_operator, 'values' => Array(values) }
  end

  it 'accepts a blank audience (everyone)' do
    expect(agent_with({})).to be_valid
    expect(agent_with('audience' => nil)).to be_valid
  end

  it 'accepts a valid tree with nested groups' do
    nested = { 'operator' => 'or', 'conditions' => [leaf('labels', 'equal_to', 'vip'), leaf('country_code', 'equal_to', 'BR')] }
    audience = { 'operator' => 'and', 'conditions' => [leaf('email', 'contains', 'acme'), nested] }
    expect(agent_with('audience' => audience)).to be_valid
  end

  it 'rejects unknown attributes, wrong operators, empty values and empty groups' do
    expect(agent_with('audience' => leaf('unknown_attr', 'equal_to', 'x'))).not_to be_valid
    expect(agent_with('audience' => leaf('name', 'contains', 'x'))).not_to be_valid
    expect(agent_with('audience' => leaf('email', 'contains', []))).not_to be_valid
    expect(agent_with('audience' => { 'operator' => 'and', 'conditions' => [] })).not_to be_valid
    expect(agent_with('audience' => { 'operator' => 'xor', 'conditions' => [leaf('email', 'is_present')] })).not_to be_valid
  end

  it 'accepts custom attributes declared for the account with their operators' do
    create(:custom_attribute_definition, account: account, attribute_model: :contact_attribute,
                                         attribute_display_type: :date, attribute_key: 'signed_up_on')

    expect(agent_with('audience' => leaf('signed_up_on', 'is_greater_than', '2024-01-01'))).to be_valid
    expect(agent_with('audience' => leaf('signed_up_on', 'contains', '2024'))).not_to be_valid
  end

  it 'rejects trees deeper than the maximum depth' do
    deep = leaf('email', 'is_present')
    3.times { deep = { 'operator' => 'and', 'conditions' => [deep] } }

    expect(agent_with('audience' => deep)).not_to be_valid
  end

  it 'validates response_window against the known windows' do
    expect(agent_with('response_window' => 'business_hours')).to be_valid
    expect(agent_with('response_window' => 'lunch')).not_to be_valid
  end
end
