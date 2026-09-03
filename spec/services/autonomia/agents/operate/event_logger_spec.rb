require 'rails_helper'

# #284 (Entrega 1) — fontes por resposta: o evento `replied` guarda a mensagem postada, os ids dos
# trechos de conhecimento usados e o modelo. Nunca conteúdo/prompt. `handed_off` aceita motivo externo.
RSpec.describe Autonomia::Agents::Operate::EventLogger do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda.')
  end

  def result(used_knowledge: [], handoff: { should: false, reason: nil })
    Autonomia::Agents::AnswerResult.new(
      reply: 'ok', confidence: 0.8, handoff: handoff, used_knowledge: used_knowledge, answered_from_knowledge: true
    )
  end

  describe '.replied' do
    it 'records the posted message, the knowledge entry ids and the model' do
      # Arrange
      message = create(:message, account: account, conversation: conversation, message_type: :outgoing)
      used = [
        { id: 11, content: 'trecho', source: 'faq' },
        { id: 11, content: 'trecho', source: 'faq' },
        { id: nil, content: '<imagem enviada>', source: 'imagem da mensagem' }
      ]

      # Act
      event = described_class.replied(agent: agent, conversation: conversation, result: result(used_knowledge: used),
                                      message: message)

      # Assert
      expect(event).to have_attributes(
        message_id: message.id, used_entry_ids: [11], model: Autonomia::Agents::Config::ANSWERER_MODEL,
        confidence: 0.8, answered_from_knowledge: true, conversation_id: conversation.id
      )
    end

    it 'keeps working without a message (legacy callers)' do
      event = described_class.replied(agent: agent, conversation: conversation, result: result)

      expect(event.message_id).to be_nil
      expect(event.used_entry_ids).to eq([])
    end

    it 'never raises when the write fails' do
      allow(Autonomia::Agents::AgentEvent).to receive(:create!).and_raise(ActiveRecord::StatementInvalid, 'boom')

      expect { described_class.replied(agent: agent, conversation: conversation, result: result) }.not_to raise_error
    end
  end

  describe '.handed_off' do
    it 'uses the explicit reason when given, curated by the allowlist' do
      event = described_class.handed_off(agent: agent, conversation: conversation, result: nil, reason: 'human_requested')
      expect(event.handoff_reason).to eq('human_requested')

      other = described_class.handed_off(agent: agent, conversation: conversation, result: nil, reason: 'cliente irritado')
      expect(other.handoff_reason).to eq('other')
    end

    it 'falls back to the result reason' do
      event = described_class.handed_off(agent: agent, conversation: conversation,
                                         result: result(handoff: { should: true, reason: 'low_confidence' }))
      expect(event.handoff_reason).to eq('low_confidence')
    end
  end

  describe '.handed_off_by_inbox' do
    it 'logs for the agent linked to the conversation inbox' do
      agent_bot = create(:agent_bot, account: account, outgoing_url: nil)
      Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: agent_bot)

      event = described_class.handed_off_by_inbox(conversation: conversation, reason: 'human_requested')

      expect(event).to be_handed_off
      expect(event.autonomia_agent_id).to eq(agent.id)
    end

    it 'is a no-op when the inbox has no Autonomia agent' do
      expect(described_class.handed_off_by_inbox(conversation: conversation, reason: 'human_requested')).to be_nil
      expect(Autonomia::Agents::AgentEvent.count).to eq(0)
    end
  end
end
