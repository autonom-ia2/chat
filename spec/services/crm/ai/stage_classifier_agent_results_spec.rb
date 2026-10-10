require 'rails_helper'

# Multifunil (#1146): o resultado das ferramentas do agente vai ao modelo junto com as mensagens.
RSpec.describe Crm::Ai::StageClassifier do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }

  it 'manda agent_results no input do classificador' do
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    card = account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Onix')
    resultado = { tool: 'cotar_seguro', summary: 'Cotação de seguro auto — Onix: menor prêmio R$ 1.950,00 (Allianz).' }
    context = { summary: '', recent_messages: [], current_stage: { id: stage.id, name: stage.name }, known_attributes: {},
                conversation_state: {}, temporal: {}, agent_results: [resultado] }
    client = instance_double(Crm::Ai::ResponsesClient)

    classifier = described_class.new(card: card, client: client, stages: [stage], context: context)

    expect(JSON.parse(classifier.send(:user_input))['agent_results']).to eq([resultado.stringify_keys])
  end
end
