require 'rails_helper'

# #1433 F1a — a escolha de quem responde, ponta a ponta no Operate: a mensagem do cliente gera UMA resposta, de quem é
# o dono da conversa; a área posta com o próprio espelho e continua dona (o claim_conversation_for_bot não devolve a
# conversa à porta); pessoa atribuída cala todo mundo. Chave da Fase 2 desligada: tudo como hoje (a porta responde).
RSpec.describe Autonomia::Agents::Operate do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }

  let!(:porta) do
    Autonomia::Agents::Operate::InboxConnector.new(agent: agente('Porta'), inbox: inbox).perform(connect: true).agent_inbox
  end
  let!(:area) { Autonomia::Agents::Areas.vincular!(agent: agente('Financeiro'), inbox: inbox) }

  def agente(nome)
    Autonomia::Agents::Agent.create!(account: account, name: nome, agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda o cliente.')
  end

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true', AI_HUMANIZE_DELIVERY: 'false', AI_AGENT_MEDIA: 'false' do
      example.run
    end
  end

  def responde_com(texto)
    answer = Autonomia::Agents::AnswerResult.new(
      reply: texto, confidence: 0.9, handoff: { should: false, reason: nil }, used_knowledge: [], answered_from_knowledge: false
    )
    allow(Autonomia::Agents::Answerer).to receive(:new).and_return(instance_double(Autonomia::Agents::Answerer, answer: answer))
  end

  def cliente_escreve(texto)
    create(:message, account: account, conversation: conversation, message_type: :incoming, content: texto)
  end

  # O caminho real do turno: o gatilho grava o debounce e o settle chama o Responder.
  def turno(message)
    Autonomia::Agents::Operate::ReplyJob.perform_now(conversation.id, message.id, 'trigger')
    Autonomia::Agents::Operate::ReplyJob.perform_now(conversation.id, message.id, 'settle')
  end

  def respostas_do_robo
    conversation.messages.outgoing.where(sender_type: 'AgentBot', private: false)
  end

  context 'when a chave da Fase 2 está ligada e a conversa está com a área' do
    before do
      Autonomia::Agents::Fase2.ligar!(account)
      conversation.update!(ai_assignee: area.agent_bot, status: :open)
    end

    it 'escolhe a área nos pontos de autorização do Operate' do
      expect(described_class.eligible_agent_inbox(conversation)).to eq(area)
      expect(described_class.authorized_agent_inbox(conversation)).to eq(area)
    end

    it 'uma mensagem do cliente gera exatamente 1 resposta, da área, com o espelho dela; a porta fica calada' do
      responde_com('Aqui é o financeiro.')

      turno(cliente_escreve('quero o boleto'))

      expect(respostas_do_robo.count).to eq(1)
      expect(respostas_do_robo.first).to have_attributes(sender_id: area.agent_bot_id, content: 'Aqui é o financeiro.')
      expect(respostas_do_robo.where(sender_id: porta.agent_bot_id)).to be_empty
    end

    it 'depois de responder, a conversa continua com a área (o claim não devolve à porta)' do
      responde_com('Segue o boleto.')

      turno(cliente_escreve('quero o boleto'))

      expect(conversation.reload).to have_attributes(assignee_agent_bot_id: area.agent_bot_id, ai_assignee_type: 'AgentBot',
                                                     status: 'open')
      expect(described_class.eligible_agent_inbox(conversation)).to eq(area)
    end

    it 'pessoa atribuída cala a área e a porta' do
      conversation.update!(assignee: create(:user, account: account, role: :agent))
      expect(Autonomia::Agents::Answerer).not_to receive(:new)

      turno(cliente_escreve('oi'))

      expect(described_class.eligible_agent_inbox(conversation)).to be_nil
      expect(respostas_do_robo).to be_empty
    end

    it 'área desligada: ninguém responde no lugar dela até a conversa voltar à porta' do
      area.agent.update!(enabled: false)

      expect(conversation.reload.assignee_agent_bot_id).to eq(porta.agent_bot_id)
      expect(described_class.eligible_agent_inbox(conversation)).to eq(porta)
    end
  end

  context 'when a chave da Fase 2 está desligada (como hoje)' do
    it 'a porta responde, mesmo com a conversa no espelho da área' do
      conversation.update!(ai_assignee: area.agent_bot, status: :open)
      responde_com('Aqui é a porta.')

      expect(described_class.eligible_agent_inbox(conversation)).to eq(porta)
      expect(described_class.authorized_agent_inbox(conversation)).to eq(porta)

      turno(cliente_escreve('oi'))

      expect(respostas_do_robo.count).to eq(1)
      expect(respostas_do_robo.first.sender_id).to eq(porta.agent_bot_id)
    end

    it 'sem área, devolve o mesmo vínculo da consulta de antes nos pontos de autorização' do
      area.destroy!
      antes = Autonomia::Agents::AgentInbox.kept.find_by(inbox_id: conversation.inbox_id, account_id: conversation.account_id)

      expect(described_class.eligible_agent_inbox(conversation)).to eq(antes)
      expect(described_class.authorized_agent_inbox(conversation)).to eq(antes)
    end
  end
end
