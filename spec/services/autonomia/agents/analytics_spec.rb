require 'rails_helper'

# #284 — resultados por conversa derivados de autonomia_agent_events + reporting_events + reports.
RSpec.describe Autonomia::Agents::Analytics do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:mirror) { create(:agent_bot, account: account, outgoing_url: nil) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Ana', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda.')
  end

  def conversation
    create(:conversation, account: account, inbox: inbox)
  end

  def replied(conv, at: 1.day.ago)
    Autonomia::Agents::AgentEvent.create!(agent: agent, account: account, conversation_id: conv.id, event_type: :replied,
                                          created_at: at)
  end

  def handed_off(conv, at: 1.day.ago)
    Autonomia::Agents::AgentEvent.create!(agent: agent, account: account, conversation_id: conv.id, event_type: :handed_off,
                                          handoff_reason: 'human_requested', created_at: at)
  end

  def core_event(conv, name, at: 1.day.ago)
    create(:reporting_event, account: account, inbox: inbox, conversation: conv, user: nil, name: name,
                             event_start_time: at - 1.hour, event_end_time: at)
  end

  describe '#call outcomes' do
    it 'counts handled, resolved without human, handed off, reopened and wrong replies inside the window' do
      # Arrange
      resolved_alone = conversation
      replied(resolved_alone)
      core_event(resolved_alone, 'conversation_resolved')

      resolved_by_human = conversation
      replied(resolved_by_human)
      create(:message, account: account, conversation: resolved_by_human, message_type: :outgoing,
                       sender: create(:user, account: account))
      core_event(resolved_by_human, 'conversation_resolved')

      signaled = conversation
      replied(signaled)
      handed_off(signaled)

      taken_by_human = conversation
      replied(taken_by_human)
      core_event(taken_by_human, 'conversation_bot_handoff')

      reopened = conversation
      replied(reopened)
      core_event(reopened, 'conversation_resolved', at: 10.days.ago) # resolvida FORA da janela, reaberta dentro
      core_event(reopened, 'conversation_opened', at: 2.days.ago)

      first_open_only = conversation
      replied(first_open_only)
      core_event(first_open_only, 'conversation_opened')

      reported = conversation
      replied(reported)
      message = create(:message, account: account, conversation: reported, message_type: :outgoing, sender: mirror)
      Captain::MessageReport.create!(message: message, user: create(:user, account: account), report_reason: 'other')

      outside = conversation
      replied(outside, at: 20.days.ago)
      core_event(outside, 'conversation_resolved', at: 20.days.ago)

      # Act
      outcomes = described_class.new(agent: agent, range: '7d').call[:outcomes]

      # Assert
      expect(outcomes).to eq(
        handled: 7, resolved_without_human: 1, handed_off: 2, reopened: 1, wrong_replies: 1
      )
    end

    it 'does not count a conversation resolved without human when it was handed off before the window' do
      conv = conversation
      handed_off(conv, at: 20.days.ago)
      replied(conv)
      core_event(conv, 'conversation_resolved')

      outcomes = described_class.new(agent: agent, range: '7d').call[:outcomes]

      expect(outcomes[:resolved_without_human]).to eq(0)
    end

    it 'never mixes agents or accounts' do
      other_agent = Autonomia::Agents::Agent.create!(account: account, name: 'Bia', agent_type: 'custom', instruction: 'x')
      conv = conversation
      Autonomia::Agents::AgentEvent.create!(agent: other_agent, account: account, conversation_id: conv.id,
                                            event_type: :replied)
      core_event(conv, 'conversation_resolved')

      outcomes = described_class.new(agent: agent, range: '7d').call[:outcomes]

      expect(outcomes.values).to all(eq(0))
    end
  end

  describe '#outcome_scope' do
    it 'returns the matching conversations and none for an unknown metric' do
      conv = conversation
      replied(conv)

      analytics = described_class.new(agent: agent, range: '30d')

      expect(analytics.outcome_scope('handled').pluck(:id)).to eq([conv.id])
      expect(analytics.outcome_scope('bogus')).to be_empty
    end
  end
end
