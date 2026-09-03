require 'rails_helper'

# Regressao: o executor referenciava Conversations::AssignmentService sem `::`. Como existe
# Crm::Conversations, o Ruby resolvia Crm::Conversations::AssignmentService e levantava NameError,
# engolido pelo rescue do Evaluator — o handoff r2_direct nunca atribuia e nao deixava erro visivel.
RSpec.describe Crm::Ai::HandoffExecutor do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:inbox) { create_crm_inbox(account: account, members: [agent]) }
  let(:conversation) { create_crm_conversation(account: account, inbox: inbox, contact: contact) }

  around do |example|
    with_modified_env CRM_KANBAN_ENABLED: 'true', CRM_AI_ENABLED: 'true' do
      example.run
    end
  end

  before do
    allow(Rails.configuration.dispatcher).to receive(:dispatch)
    allow(OnlineStatusTracker).to receive(:get_available_users).with(account.id).and_return({ agent.id => 'online' })
  end

  def build_card
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    stage.update!(metadata: { 'ai_handoff' => { 'enabled' => true, 'handoff_mode' => 'r2_direct' } })
    account.crm_cards.create!(
      pipeline: pipeline, stage: stage, inbox: inbox, contact: contact,
      primary_conversation: conversation, title: 'Lead handoff', metadata: { 'ai' => {} }
    )
  end

  it 'assigns the conversation to the selected agent in r2_direct mode' do
    card = build_card

    result = described_class.new(card: card, handoff: { intent: 'transferir', reason: 'cliente pediu humano' }).perform

    expect(result.status).to eq(:handed_off)
    expect(result.assignee).to eq(agent)
    expect(conversation.reload.assignee_id).to eq(agent.id)
    # Sem o stamp o cooldown nao segura um segundo disparo.
    expect(card.reload.metadata.dig('ai', 'last_handoff_at')).to be_present
  end

  # #284 — caixa com agente Autonom.ia: o handoff do CRM entra no histórico do agente (aba Desempenho).
  it 'logs a handed_off event for the Autonomia agent linked to the inbox' do
    card = build_card
    autonomia_agent = Autonomia::Agents::Agent.create!(account: account, name: 'Ana', agent_type: 'custom', status: :active,
                                                       enabled: true, instruction: 'Atenda.')
    mirror = AgentBot.create!(account: account, name: 'Ana', bot_type: :webhook, outgoing_url: nil)
    Autonomia::Agents::AgentInbox.create!(agent: autonomia_agent, inbox: inbox, account: account, agent_bot: mirror)

    described_class.new(card: card, handoff: { intent: 'transferir', reason: 'cliente pediu humano' }).perform

    event = Autonomia::Agents::AgentEvent.handed_off.find_by(conversation_id: conversation.id)
    expect(event).to have_attributes(autonomia_agent_id: autonomia_agent.id, handoff_reason: 'human_requested')
  end
end
