require 'rails_helper'

# #1035 — pausar/desligar/excluir o agente devolve as conversas para a equipe; voltar a atender reativa
# o espelho. Antes, a conversa ficava com o bot (que não responde) e a distribuição automática a pulava.
RSpec.describe Autonomia::Agents::Agent do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:inbox) { create(:inbox, account: account) }
  let(:agent) do
    described_class.create!(account: account, name: 'Bot', agent_type: 'custom', status: :active, enabled: true,
                            actuation: :external, instruction: 'Atenda.')
  end
  let(:mirror) { Autonomia::Agents::AgentInbox.find_by!(inbox_id: inbox.id).agent_bot }
  let(:mirror_bot_inbox) { AgentBotInbox.find_by!(inbox_id: inbox.id, agent_bot_id: mirror.id) }

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true' do
      example.run
    end
  end

  before do
    result = Autonomia::Agents::Operate::InboxConnector.new(agent: agent, inbox: inbox).perform(connect: true)
    raise 'connect failed' unless result.success?
  end

  def held_conversation
    create(:conversation, account: account, inbox: inbox, status: :open, assignee_agent_bot_id: mirror.id)
  end

  it 'starts new conversations with the mirror while the agent is operating (baseline)' do
    expect(create(:conversation, account: account, inbox: inbox).assignee_agent_bot_id).to eq(mirror.id)
  end

  describe 'pausing' do
    it 'hands held and pending conversations back to the team' do
      held = held_conversation
      pending = create(:conversation, account: account, inbox: inbox, status: :pending, assignee_agent_bot_id: mirror.id)

      agent.update!(status: :paused)

      expect(held.reload).to have_attributes(status: 'open', assignee_agent_bot_id: nil)
      expect(pending.reload).to have_attributes(status: 'open', assignee_agent_bot_id: nil)
    end

    it 'inactivates the mirror so new conversations are born without the bot' do
      agent.update!(status: :paused)

      expect(mirror_bot_inbox.reload).to be_inactive
      expect(inbox.reload.active_bot?).to be(false)
      expect(create(:conversation, account: account, inbox: inbox).assignee_agent_bot_id).to be_nil
    end

    it 'does not touch conversations already with a person' do
      person = create(:user, account: account)
      create(:inbox_member, inbox: inbox, user: person)
      with_person = create(:conversation, account: account, inbox: inbox, status: :open, assignee: person)

      agent.update!(status: :paused)

      expect(with_person.reload.assignee_id).to eq(person.id)
    end

    it 'does not touch conversations of another inbox' do
      other_inbox = create(:inbox, account: account)
      other = create(:conversation, account: account, inbox: other_inbox, status: :pending)

      agent.update!(status: :paused)

      expect(other.reload.status).to eq('pending')
    end

    it 'also hands back when the agent is switched off (enabled: false)' do
      held = held_conversation

      agent.update!(enabled: false)

      expect(held.reload.assignee_agent_bot_id).to be_nil
      expect(mirror_bot_inbox.reload).to be_inactive
    end
  end

  describe 'resuming' do
    it 'reactivates the mirror so the agent takes new conversations again' do
      agent.update!(status: :paused)

      agent.update!(status: :active)

      expect(mirror_bot_inbox.reload).to be_active
      expect(create(:conversation, account: account, inbox: inbox).assignee_agent_bot_id).to eq(mirror.id)
    end

    it 'keeps handed-back conversations with the team' do
      held = held_conversation
      agent.update!(status: :paused)

      agent.update!(status: :active)

      expect(held.reload.assignee_agent_bot_id).to be_nil
    end
  end

  # Segurança de produção: só a TRANSIÇÃO de atender ↔ não atender mexe em conversa e espelho.
  describe 'edits that keep the agent operating' do
    it 'leaves held conversations and the mirror alone' do
      held = held_conversation

      agent.update!(name: 'Bot novo', instruction: 'Atenda com calma.', tone: 'calmo')

      expect(held.reload.assignee_agent_bot_id).to eq(mirror.id)
      expect(mirror_bot_inbox.reload).to be_active
    end

    it 'does nothing when a paused agent stays off (paused → draft)' do
      agent.update!(status: :paused)
      held_later = create(:conversation, account: account, inbox: inbox, status: :pending)

      agent.update!(status: :draft)

      expect(held_later.reload.status).to eq('pending')
      expect(mirror_bot_inbox.reload).to be_inactive
    end
  end

  describe 'destroying' do
    it 'hands held conversations back to the team and removes the mirror' do
      held = held_conversation
      pending = create(:conversation, account: account, inbox: inbox, status: :pending, assignee_agent_bot_id: mirror.id)

      agent.destroy!

      expect(held.reload.assignee_agent_bot_id).to be_nil
      # Sem a liberação, a conversa em espera ficava `pending` para sempre (o espelho só some).
      expect(pending.reload.status).to eq('open')
      expect(AgentBotInbox.where(inbox_id: inbox.id)).to be_empty
    end
  end
end
