require 'rails_helper'

# #284 — fechar o ciclo do ai_assignee: ao desconectar, libera TAMBÉM as conversas `open` que ainda
# têm o espelho como ai_assignee (na caixa do espelho as conversas nascem open), não só as pending.
RSpec.describe Autonomia::Agents::Operate::InboxConnector do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:inbox) { create(:inbox, account: account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom', status: :active, enabled: true,
                                     actuation: :external, instruction: 'Atenda.')
  end

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true' do
      example.run
    end
  end

  describe '#disconnect!' do
    it 'releases pending conversations and open conversations still held by the mirror bot' do
      # Arrange — conecta (cria o espelho) e monta três conversas: pending, open com espelho, open sem espelho.
      described_class.new(agent: agent, inbox: inbox).perform(connect: true)
      mirror = Autonomia::Agents::AgentInbox.find_by!(inbox_id: inbox.id).agent_bot
      pending = create(:conversation, account: account, inbox: inbox, status: :pending, assignee_agent_bot_id: mirror.id)
      held = create(:conversation, account: account, inbox: inbox, status: :open, assignee_agent_bot_id: mirror.id)
      untouched = create(:conversation, account: account, inbox: inbox, status: :open)

      # Act
      result = described_class.new(agent: agent, inbox: inbox).perform(connect: false)

      # Assert
      expect(result).to be_success
      expect(pending.reload).to have_attributes(status: 'open', assignee_agent_bot_id: nil)
      expect(held.reload).to have_attributes(status: 'open', assignee_agent_bot_id: nil)
      expect(untouched.reload.status).to eq('open')
      expect(Autonomia::Agents::AgentInbox.where(inbox_id: inbox.id)).to be_empty
    end
  end
end
