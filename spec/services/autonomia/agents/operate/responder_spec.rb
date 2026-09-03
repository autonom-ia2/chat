require 'rails_helper'

RSpec.describe Autonomia::Agents::Operate::Responder do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:agent_bot) { create(:agent_bot, account: account) }

  let(:agent) do
    Autonomia::Agents::Agent.create!(
      account: account, name: 'Bot', agent_type: 'custom', status: :active, enabled: true,
      instruction: 'Atenda o cliente.'
    )
  end

  let(:agent_inbox) do
    Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: agent_bot)
  end

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true' do
      example.run
    end
  end

  describe 'pre-answer eligibility recheck (C4)' do
    it 'never calls the LLM when the conversation became ineligible before answering' do
      # Arrange: humano assumiu a conversa entre o debounce e o perform
      conversation.update!(assignee: create(:user, account: account, role: :agent))
      expect(Autonomia::Agents::Answerer).not_to receive(:new)

      # Act
      result = described_class.new(conversation: conversation, agent_inbox: agent_inbox).perform

      # Assert
      expect(result.status).to eq(:silenced)
    end

    it 'still calls the answerer when the conversation remains eligible' do
      # Arrange: conversa sem responsável + vínculo ativo -> elegível; IA devolve silêncio (nada a postar)
      silent = Autonomia::Agents::AnswerResult.new(
        reply: nil, confidence: 0.0, handoff: { should: false, reason: nil },
        used_knowledge: [], answered_from_knowledge: false, raw_reply: nil, error: 'ai_unavailable'
      )
      answerer = instance_double(Autonomia::Agents::Answerer, answer: silent)
      expect(Autonomia::Agents::Answerer).to receive(:new).and_return(answerer)

      # Act
      result = described_class.new(conversation: conversation, agent_inbox: agent_inbox).perform

      # Assert
      expect(result.status).to eq(:silenced)
    end
  end

  # #284 — fontes por resposta + sinal de handoff da instrução. Caminho clássico (humanização OFF).
  describe 'reply sources and handoff signal' do
    let(:knowledge) { [{ id: 7, content: 'Entregamos em 2 dias.', source: 'faq' }] }

    def stub_answer(handoff:)
      answer = Autonomia::Agents::AnswerResult.new(
        reply: 'Entregamos em 2 dias.', confidence: 0.9, handoff: handoff,
        used_knowledge: knowledge, answered_from_knowledge: true
      )
      allow(Autonomia::Agents::Answerer).to receive(:new).and_return(instance_double(Autonomia::Agents::Answerer, answer: answer))
    end

    around do |example|
      with_modified_env AI_HUMANIZE_DELIVERY: 'false', AI_AGENT_MEDIA: 'false' do
        example.run
      end
    end

    before do
      conversation.update!(assignee_agent_bot_id: agent_bot.id)
      create(:message, account: account, conversation: conversation, message_type: :incoming, content: 'prazo?')
    end

    it 'links the replied event to the posted message with the knowledge entry ids' do
      # Arrange
      stub_answer(handoff: { should: false, reason: nil })

      # Act
      result = described_class.new(conversation: conversation, agent_inbox: agent_inbox).perform

      # Assert
      event = Autonomia::Agents::AgentEvent.replied.last
      expect(result.status).to eq(:replied)
      expect(event.message_id).to eq(result.message.id)
      expect(event.used_entry_ids).to eq([7])
      expect(event.model).to eq(Autonomia::Agents::Config::ANSWERER_MODEL)
      # Sem sinal de handoff: o espelho continua no comando e nada muda no ciclo.
      expect(conversation.reload.assignee_agent_bot_id).to eq(agent_bot.id)
      expect(Autonomia::Agents::AgentEvent.handed_off.count).to eq(0)
    end

    it 'posts the same reply, releases the mirror bot and logs handed_off when the instruction signals handoff' do
      # Arrange
      stub_answer(handoff: { should: true, reason: 'human_requested' })

      # Act
      result = described_class.new(conversation: conversation, agent_inbox: agent_inbox).perform

      # Assert — a resposta ao cliente é a mesma; o que muda é o ciclo do ai_assignee.
      expect(result.status).to eq(:replied)
      expect(result.message.content).to eq('Entregamos em 2 dias.')
      expect(conversation.reload).to have_attributes(status: 'open', assignee_agent_bot_id: nil)
      expect(Autonomia::Agents::AgentEvent.handed_off.last.handoff_reason).to eq('human_requested')
    end

    it 'does not log handoff twice once the mirror bot was already released' do
      # Arrange — ciclo já fechado (sem ai_assignee, open).
      conversation.update!(assignee_agent_bot_id: nil, status: :open)
      stub_answer(handoff: { should: true, reason: 'human_requested' })

      # Act
      described_class.new(conversation: conversation, agent_inbox: agent_inbox).perform

      # Assert
      expect(Autonomia::Agents::AgentEvent.handed_off.count).to eq(0)
    end
  end
end
