require 'rails_helper'

# Contrato do prompt e do schema do cérebro de follow-up.
#
# NÃO avalia o julgamento do modelo — isso exigiria chamar a API de verdade. O que este spec
# garante é que as regras acordadas continuam chegando ao modelo: se alguém apagar a regra da
# confirmação passiva ou o default "na dúvida, empresa", o teste quebra.
RSpec.describe Crm::Ai::FollowUpComposer do
  subject(:composer) { described_class.new(card: nil, client: nil, context: {}) }

  let(:instructions) { composer.send(:instructions) }

  it 'requires the AI to state whose turn it is and what kind of message it wrote' do
    schema = described_class::COMPOSE_SCHEMA[:schema]

    expect(schema[:properties][:next_action_owner][:enum]).to eq(%w[cliente empresa terceiro])
    expect(schema[:properties][:message_kind][:enum]).to eq(%w[cobranca aviso_andamento])
    expect(schema[:required]).to include('next_action_owner', 'message_kind')
  end

  it 'treats a passive confirmation as our turn, not as customer silence' do
    expect(instructions).to include('vou aguardar')
    expect(instructions).to include('Na dúvida, escolha "empresa"')
  end

  it 'forbids charging the customer when the next action is not theirs' do
    expect(instructions).to include('NÃO cobre e NÃO peça nada')
    expect(instructions).to include('aviso_andamento')
  end

  it 'no longer claims the customer vanished based on who spoke last' do
    expect(instructions).not_to include('nós perguntamos e ele sumiu')
    expect(instructions).to include('Quem falou por último NÃO define, sozinho, de quem é a pendência')
  end
end
