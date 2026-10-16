require 'rails_helper'

# A regra do funil apontando o agente de IA: a conversa reaberta com a dona offline vai para ele.
RSpec.describe Crm::Entrega::Reabertura do
  include_context 'with crm responsible agent'

  let(:ana) { create(:user, account: account, role: :agent, name: 'Ana') }

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true', AI_HUMANIZE_DELIVERY: 'false', AI_AGENT_MEDIA: 'false' do
      example.run
    end
  end

  before do
    account.enable_features!(Crm::Conversations::OutroCanal::FLAG)
    create(:inbox_member, inbox: inbox, user: ana)
    allow(OnlineStatusTracker).to receive(:get_available_users).and_return({})
    create_card(pipeline: comercial)
    comercial.stages.first.update!(metadata: { 'ai_handoff' => { 'enabled' => true, 'handoff_mode' => 'r2_direct',
                                                                 'pool_type' => 'ai_agent', 'pool_id' => area.id } })
    conversation.reload.update!(assignee: ana, ai_assignee: nil, status: :resolved)
  end

  # Pega: "inclusive passando ao agente de IA" ficar de fora na reabertura.
  it 'dona offline: a conversa passa à área de IA da regra', :aggregate_failures do
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: 'Oi')

    expect(conversation.reload).to have_attributes(status: 'open', assignee_id: nil, ai_assignee: espelho_area)
  end
end
