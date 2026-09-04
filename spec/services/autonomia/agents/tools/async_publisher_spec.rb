require 'rails_helper'

RSpec.describe Autonomia::Agents::Tools::AsyncPublisher do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:agent_bot) { create(:agent_bot, account: account) }

  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom',
                                     status: :active, enabled: true, instruction: 'Atenda o cliente.')
  end

  let(:agent_inbox) do
    Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: agent_bot)
  end

  let(:run) do
    Autonomia::Agents::ToolRun.open!(agent: agent, slug: 'consultar_cotacao',
                                     arguments: { 'ano' => '2019' },
                                     scope: { conversation_id: conversation.id,
                                              agent_inbox_id: agent_inbox.id })
  end

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true' do
      example.run
    end
  end

  # Promove a execução para `running` (é o que o dispatcher faz no fim do turno). Sem promoção não
  # existe entrega: o publicador só é chamado a partir de uma execução viva.
  def promote(origin_message_id: nil, expected_chunks: 0)
    run.update!(origin_message_id: origin_message_id)
    run.promote!(expected_chunks: expected_chunks,
                 notify_customer: false, expires_at: 3.minutes.from_now)
    run
  end

  def bot_messages
    conversation.reload.messages.where(sender_type: 'AgentBot')
  end

  # A conversa pode mudar de CAIXA entre o disparo e a entrega (o AgentInbox é resolvido pelo inbox
  # atual). Nesse caso a cotação já não é deste vínculo e não pode ser publicada por ele.
  describe 'when the binding changed after the run started' do
    it 'blocks the delivery when the conversation moved to another inbox' do
      # Arrange
      promote
      other_inbox = create(:inbox, account: account)
      other_bot = create(:agent_bot, account: account)
      Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: other_inbox, account: account,
                                            agent_bot: other_bot)
      conversation.update!(inbox: other_inbox)

      # Act
      result = described_class.new(run: run).publish('cotação pronta')

      # Assert
      expect(result).to be_blocked
      expect(bot_messages).to be_empty
      expect(run.reload.sequence).to eq(0)
    end
  end

  describe 'publishing the delivery' do
    it 'posts an outgoing AgentBot message stamped with the delivery token and advances the sequence' do
      # Arrange
      promote
      token = run.delivery_token(0)

      # Act
      result = described_class.new(run: run).publish('encontrei 3 opções de cotação')

      # Assert
      expect(result).to be_published
      message = bot_messages.last
      expect(message.content).to eq('encontrei 3 opções de cotação')
      expect(message.message_type).to eq('outgoing')
      expect(message.content_attributes['autonomia_async_token']).to eq(token)
      expect(message.content_attributes['autonomia_async_slug']).to eq('consultar_cotacao')
      expect(run.reload.sequence).to eq(1)
    end

    it 'never stamps autonomia_reply_to_message_id on the delivered message' do
      # Arrange: origem presente é justamente o caso em que herdar o carimbo seria tentador
      origin = create(:message, account: account, conversation: conversation, message_type: :incoming, content: 'cota aí')
      promote(origin_message_id: origin.id)

      # Act
      described_class.new(run: run).publish('cotação pronta')

      # Assert: o `already_replied?` do Responder é um regex sobre esse carimbo — herdá-lo faria a
      # resposta real do turno ser descartada em silêncio.
      attributes = bot_messages.last.content_attributes.to_h
      expect(attributes).not_to have_key('autonomia_reply_to_message_id')
      expect(attributes.keys).to include('autonomia_async_token')
    end

    it 'returns skipped and posts nothing when the text is blank' do
      # Arrange
      promote

      # Act
      result = described_class.new(run: run).publish('   ')

      # Assert
      expect(result.status).to eq(:skipped)
      expect(bot_messages.count).to eq(0)
    end
  end

  describe 'idempotency across a retry' do
    it 'creates a single message when the same sequence is published twice' do
      # Arrange: o retry do Sidekiq relê a linha ANTES do avanço da sequência — é essa cópia velha
      # que reexecuta a publicação.
      promote
      stale_run = Autonomia::Agents::ToolRun.find(run.id)

      # Act
      first = described_class.new(run: run).publish('cotação: 3 opções')
      second = described_class.new(run: stale_run).publish('cotação: 3 opções')

      # Assert
      expect(first).to be_published
      expect(second).to be_published
      expect(second.message).to be_nil
      expect(bot_messages.count).to eq(1)
      expect(run.reload.sequence).to eq(1)
    end
  end

  describe 'conversation with a human assignee' do
    let(:assignee) { create(:user, account: account, role: :agent) }

    it 'publishes the delivery as a private note instead of staying silent' do
      # Arrange
      promote
      conversation.update!(assignee: assignee)

      # Act
      result = described_class.new(run: run).publish('cotação pronta para o corretor')

      # Assert
      expect(result).to be_published
      message = bot_messages.last
      expect(message.private).to be(true)
      expect(message.content).to eq('cotação pronta para o corretor')
    end
  end

  describe 'authorization gates' do
    it 'blocks the delivery when the agent was turned off' do
      # Arrange
      promote
      agent.update!(enabled: false)

      # Act
      result = described_class.new(run: run).publish('cotação pronta')

      # Assert
      expect(result).to be_blocked
      expect(bot_messages.count).to eq(0)
    end

    it 'blocks the delivery when the account feature was turned off' do
      # Arrange
      promote
      account.update!(internal_attributes: { 'autonomia_agents_enabled' => false })

      # Act
      result = described_class.new(run: run).publish('cotação pronta')

      # Assert
      expect(result).to be_blocked
      expect(bot_messages.count).to eq(0)
    end
  end

  describe 'humanized chain deferral' do
    let(:origin) do
      create(:message, account: account, conversation: conversation, message_type: :incoming, content: 'quero cotar')
    end

    def post_last_chunk
      create(:message, account: account, conversation: conversation, inbox: inbox, sender: agent_bot,
                       message_type: :outgoing, content: 'já te trago os valores',
                       content_attributes: { 'autonomia_chunk_token' => "#{origin.id}:2" })
    end

    it 'defers while the last expected chunk of the turn has not been posted' do
      # Arrange: cadeia de 3 pedaços; o último ("<origin>:2") ainda não saiu
      promote(origin_message_id: origin.id, expected_chunks: 3)

      # Act
      result = described_class.new(run: run).publish('encontrei 3 opções')

      # Assert
      expect(result).to be_deferred
      expect(bot_messages.count).to eq(0)
      expect(run.reload.sequence).to eq(0)
    end

    it 'publishes once the last expected chunk is on the conversation' do
      # Arrange
      promote(origin_message_id: origin.id, expected_chunks: 3)
      post_last_chunk

      # Act
      result = described_class.new(run: run).publish('encontrei 3 opções')

      # Assert
      expect(result).to be_published
      expect(bot_messages.last.content_attributes['autonomia_async_token']).to be_present
    end

    it 'publishes anyway through publish! even with the chain still open' do
      # Arrange: teto de adiamentos estourado — mensagem fora de ordem é ruim, mensagem que nunca
      # chega é pior.
      promote(origin_message_id: origin.id, expected_chunks: 3)

      # Act
      result = described_class.new(run: run).publish!('encontrei 3 opções')

      # Assert
      expect(result).to be_published
      expect(bot_messages.count).to eq(1)
      expect(run.reload.sequence).to eq(1)
    end
  end
end
