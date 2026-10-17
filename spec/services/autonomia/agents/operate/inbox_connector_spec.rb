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

    # #1433 — soltar a porta deixa as áreas na caixa (que passa a ser só de pessoas); soltar a área não toca a porta.
    context 'with agente da equipe (área) na caixa' do
      let(:da_equipe) do
        Autonomia::Agents::Agent.create!(account: account, name: 'Equipe', agent_type: 'custom', status: :active, enabled: true)
      end

      before { described_class.new(agent: agent, inbox: inbox).perform(connect: true) }

      it 'soltar a porta deixa as áreas e as conversas delas; a caixa fica sem robô (só de pessoas)' do
        area = Autonomia::Agents::Areas.vincular!(agent: da_equipe, inbox: inbox)
        da_area = create(:conversation, account: account, inbox: inbox).tap { |c| c.update!(ai_assignee: area.agent_bot, status: :open) }

        expect(described_class.new(agent: agent, inbox: inbox).perform(connect: false)).to be_success

        expect(Autonomia::Agents::AgentInbox.kept.where(inbox_id: inbox.id)).to contain_exactly(area)
        expect(da_area.reload).to have_attributes(status: 'open', assignee_agent_bot_id: area.agent_bot_id)
        expect(inbox.reload.agent_bot).to be_nil
        expect(da_equipe.reload).to be_operating
      end

      it 'soltar a área pelo conector não toca a porta, e a caixa segue ocupada só pela porta' do
        Autonomia::Agents::Areas.vincular!(agent: da_equipe, inbox: inbox)

        expect(described_class.new(agent: da_equipe, inbox: inbox).perform(connect: false)).to be_success

        expect(Autonomia::Agents::AgentInbox.kept.where(inbox_id: inbox.id).pluck(:papel)).to eq(['porta'])
        expect(inbox.reload.agent_bot).to be_present
      end
    end
  end
end
