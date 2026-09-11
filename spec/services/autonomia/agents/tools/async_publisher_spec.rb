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

  # Guardas que a revisão adversarial trouxe (#313).
  describe 'when the run is no longer the live one' do
    it 'refuses to publish a superseded run, so the customer never gets the corrected quote twice' do
      # Arrange — o cliente corrigiu o pedido e a execução antiga foi substituída
      promote
      run.update!(status: 'superseded')

      # Act
      result = described_class.new(run: run).publish('cotação do carro ERRADO: R$ 1.200')

      # Assert
      expect(result).to be_blocked
      expect(bot_messages).to be_empty
    end
  end

  # Um pedaço ÚNICO também não foi postado: está agendado com atraso de até 15s. Publicar sem esperar
  # entregaria a cotação antes da frase que a promete.
  describe 'ordering against a single-chunk humanized reply' do
    it 'waits for the only chunk of the turn before publishing' do
      # Arrange
      promote(origin_message_id: 4242, expected_chunks: 1)

      # Act
      before_chunk = described_class.new(run: run).publish('cotação pronta')
      create(:message, account: account, conversation: conversation, message_type: :outgoing,
                       sender: agent_bot, content: 'deixa eu consultar aqui',
                       content_attributes: { 'autonomia_chunk_token' => '4242:0' })
      after_chunk = described_class.new(run: run).publish('cotação pronta')

      # Assert
      expect(before_chunk).to be_deferred
      expect(after_chunk).to be_published
      expect(bot_messages.order(:id).last.content).to eq('cotação pronta')
    end
  end

  describe 'publishing the delivery' do
    it 'posts an outgoing AgentBot message stamped with the delivery token and advances the sequence' do
      # Arrange
      promote
      token = run.delivery_token('encontrei 3 opções de cotação')

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

  # A ENTREGA DE ARQUIVO (entrega 11): o comparativo em PDF vai como ANEXO da mensagem, com o nome
  # que o cliente vai procurar depois. Quando o download falha, vai o texto de reserva com o link —
  # o mesmo de antes —, registrado, e nunca em silêncio. A identidade é uma só nos dois caminhos.
  describe 'entrega de arquivo' do
    let(:url) { 'https://arquivos.exemplo.test/comparativo-9.pdf' }
    let(:arquivo) do
      Autonomia::Agents::Tools::EntregaDeArquivo.new(url: url, nome: 'Comparativo de seguro — placa ABC1D23.pdf',
                                                     legenda: 'Comparativo com todas as opções.',
                                                     reserva: "Comparativo com todas as opções:\n#{url}")
    end
    let(:pdf) { "%PDF-1.4\n%%EOF\n" }

    it 'publica o PDF como anexo, com o nome do arquivo' do
      # Arrange
      promote
      stub_request(:get, url).to_return(status: 200, body: pdf, headers: { 'Content-Type' => 'application/pdf' })

      # Act
      result = described_class.new(run: run).publish(arquivo.to_h)

      # Assert
      expect(result).to be_published
      anexo = bot_messages.sole.attachments.sole
      expect(anexo.file_type).to eq('file')
      expect(anexo.file.filename.to_s).to eq('Comparativo de seguro — placa ABC1D23.pdf')
      expect(anexo.file.content_type).to eq('application/pdf')
      expect(anexo.file.download).to eq(pdf)
    end

    it 'poe a legenda sem link na mensagem, com o token da identidade do arquivo' do
      # Arrange
      promote
      stub_request(:get, url).to_return(status: 200, body: pdf, headers: { 'Content-Type' => 'application/pdf' })

      # Act
      described_class.new(run: run).publish(arquivo.to_h)

      # Assert
      mensagem = bot_messages.sole
      expect(mensagem.content).to eq('Comparativo com todas as opções.')
      expect(mensagem.content).not_to include('http')
      expect(mensagem.content_attributes['autonomia_async_token']).to eq(run.delivery_token(arquivo.identidade))
      expect(run.reload.sequence).to eq(1)
    end

    it 'cai para o texto com o link quando o download falha, e registra o motivo' do
      # Arrange — o 404 real de 11/09/2026 (blob do portal inexistente)
      promote
      stub_request(:get, url).to_return(status: 404, body: '<Error><Code>BlobNotFound</Code></Error>',
                                        headers: { 'Content-Type' => 'application/xml' })
      allow(Rails.logger).to receive(:warn).and_call_original

      # Act
      result = described_class.new(run: run).publish(arquivo.to_h)

      # Assert
      expect(result).to be_published
      mensagem = bot_messages.sole
      expect(mensagem.content).to eq("Comparativo com todas as opções:\n#{url}")
      expect(mensagem.attachments).to be_empty
      expect(Rails.logger).to have_received(:warn).with(a_string_matching(/arquivo indisponivel run=#{run.id} motivo=http_404/))
    end

    it 'nao publica de novo o que ja saiu, nem como arquivo por cima do link' do
      # Arrange — a primeira publicação saiu como link; o retry encontra o arquivo no ar
      promote
      stub_request(:get, url).to_return({ status: 404, body: 'x' }, { status: 200, body: pdf, headers: { 'Content-Type' => 'application/pdf' } })
      publisher = described_class.new(run: run)
      publisher.publish(arquivo.to_h)

      # Act
      result = publisher.publish(arquivo.to_h)

      # Assert
      expect(result).to be_published
      expect(bot_messages.count).to eq(1)
      expect(run.reload.sequence).to eq(1)
    end

    it 'espera a cadeia humanizada como qualquer entrega, sem baixar nada antes da hora' do
      # Arrange
      promote(origin_message_id: 77, expected_chunks: 1)
      stub_request(:get, url).to_return(status: 200, body: pdf)

      # Act
      result = described_class.new(run: run).publish(arquivo.to_h)

      # Assert
      expect(result).to be_deferred
      expect(a_request(:get, url)).not_to have_been_made
    end
  end
end
