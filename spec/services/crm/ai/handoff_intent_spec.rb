require 'rails_helper'

# A leitura do pedido de passagem que o classificador devolve (extraída do Evaluator no #1234).
RSpec.describe Crm::Ai::HandoffIntent do
  it 'transferir pede a passagem, mesmo com should_handoff falso' do
    expect(described_class.requested?({ intent: 'transferir', should_handoff: false })).to be(true)
  end

  it 'continuar e consultar não pedem, mesmo com should_handoff verdadeiro' do
    expect(described_class.requested?({ intent: 'continuar', should_handoff: true })).to be(false)
    expect(described_class.requested?({ 'intent' => 'consultar', 'should_handoff' => true })).to be(false)
  end

  it 'sem intenção, vale o should_handoff' do
    expect(described_class.requested?({ should_handoff: 'true' })).to be(true)
    expect(described_class.requested?({ should_handoff: false })).to be(false)
  end

  it 'sem pedido nenhum, não passa' do
    expect(described_class.requested?(nil)).to be(false)
    expect(described_class.requested?({})).to be(false)
  end
end
