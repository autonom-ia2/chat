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

    # O `SafeFetch` resolve o nome antes de conectar (é assim que ele confere o endereço): o host de
    # teste ganha um endereço público, e o WebMock responde a chamada.
    before do
      allow(Resolv).to receive(:getaddresses).and_call_original
      allow(Resolv).to receive(:getaddresses).with('arquivos.exemplo.test').and_return(['93.184.216.34'])
    end

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
      # O blob ANEXADO nunca vai para a limpeza: `download` ainda funcionaria com o `PurgeJob`
      # só enfileirado, então a afirmação é sobre a fila (rodada 5, 11/09/2026).
      expect(ActiveStorage::PurgeJob).not_to have_been_enqueued
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
      # Arrange — o 404 do armazenamento do portal (XML de `BlobNotFound`)
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

    # O que ninguém no caminho classifica (uma resposta HTTP malformada do servidor do blob) subia
    # cru: `blocked`, nem arquivo nem link, com a sentinela do comparativo já gravada no caminho da
    # consulta — o "anexo que só funciona quando tudo dá certo" por uma fresta (rodada 5, P3).
    it 'cai para o texto com o link quando a camada HTTP levanta o que ninguem classifica' do
      # Arrange
      promote
      stub_request(:get, url).to_raise(Net::HTTPBadResponse)
      allow(Rails.logger).to receive(:warn).and_call_original

      # Act
      result = described_class.new(run: run).publish(arquivo.to_h)

      # Assert
      expect(result).to be_published
      mensagem = bot_messages.sole
      expect(mensagem.content).to eq("Comparativo com todas as opções:\n#{url}")
      expect(mensagem.attachments).to be_empty
      expect(Rails.logger).to have_received(:warn)
        .with(a_string_matching(/arquivo indisponivel run=#{run.id} motivo=download causa=Net::HTTPBadResponse; vai como link/))
    end

    it 'nao publica de novo o que ja saiu, nem como arquivo por cima do link' do
      # Arrange — a primeira publicação saiu como link; o retry encontra o arquivo no ar
      promote
      stub_request(:get, url).to_return({ status: 404, body: 'x' }, { status: 200, body: pdf, headers: { 'Content-Type' => 'application/pdf' } })
      publisher = described_class.new(run: run)
      publisher.publish(arquivo.to_h)

      # Act
      result = publisher.publish(arquivo.to_h)

      # Assert — e o blob que o retry gravou antes de ver a mensagem no ar não fica sem dono: a
      # limpeza é em segundo plano (rodada 4), então o que se afirma é que ela foi AGENDADA e que,
      # feita, não sobra blob nenhum
      expect(result).to be_published
      expect(bot_messages.count).to eq(1)
      expect(run.reload.sequence).to eq(1)
      expect(ActiveStorage::PurgeJob).to have_been_enqueued.once
      perform_enqueued_jobs(only: ActiveStorage::PurgeJob)
      expect(ActiveStorage::Blob.count).to eq(0)
    end

    # A LIMPEZA DO BLOB SEM DONO NÃO FALA COM O RESULTADO (rodada 4, P3). Apagar o blob do retry na
    # hora era falar com o armazenamento de novo, dentro do `ensure`: um `delete` que falha (rede)
    # saía do `ensure` por cima do resultado — a entrega que JÁ estava no ar virava `blocked` e
    # "publish failed" no log, e a linha do blob, destruída antes do `delete`, deixava o arquivo
    # órfão no armazenamento. A limpeza agora é um job: o resultado da publicação é o da publicação.
    it 'mantem a entrega publicada quando o armazenamento falha ao apagar o blob do retry' do
      # Arrange — a primeira publicação saiu como anexo; o retry grava um segundo blob e acha a
      # mensagem no ar, e o armazenamento não responde ao apagar
      promote
      stub_request(:get, url).to_return(status: 200, body: pdf, headers: { 'Content-Type' => 'application/pdf' })
      publisher = described_class.new(run: run)
      publisher.publish(arquivo.to_h)
      allow(ActiveStorage::Blob.service).to receive(:delete).and_raise(Errno::ECONNREFUSED)
      allow(Rails.logger).to receive(:warn).and_call_original

      # Act
      result = publisher.publish(arquivo.to_h)

      # Assert — publicado, uma mensagem só, nada de "publish failed"; a limpeza ficou agendada e
      # a linha do blob do retry continua inteira (nada foi destruído pela metade)
      expect(result).to be_published
      expect(bot_messages.count).to eq(1)
      expect(Rails.logger).not_to have_received(:warn).with(a_string_matching(/publish failed/))
      expect(ActiveStorage::PurgeJob).to have_been_enqueued.once
      expect(ActiveStorage::Blob.count).to eq(2)
    end

    # E quando a PUBLICAÇÃO levanta, o log tem de dizer a causa DELA: com a limpeza síncrona, um
    # `delete` que falhasse no `ensure` trocava a exceção original pela do purge, e o log passava a
    # apontar para o armazenamento em vez de para o que derrubou a mensagem (rodada 4, P3).
    it 'registra a causa da publicacao que levantou, e nao a da limpeza do blob' do
      # Arrange — download bom, mensagem que não nasce, armazenamento que não apaga
      promote
      stub_request(:get, url).to_return(status: 200, body: pdf, headers: { 'Content-Type' => 'application/pdf' })
      allow(Messages::MessageBuilder).to receive(:new).and_raise(ActiveRecord::ConnectionTimeoutError)
      allow(ActiveStorage::Blob.service).to receive(:delete).and_raise(Errno::ECONNREFUSED)
      allow(Rails.logger).to receive(:warn).and_call_original

      # Act
      result = described_class.new(run: run).publish(arquivo.to_h)

      # Assert
      expect(result).to be_blocked
      expect(bot_messages.count).to eq(0)
      expect(Rails.logger).to have_received(:warn)
        .with(a_string_matching(/publish failed run=#{run.id} ActiveRecord::ConnectionTimeoutError/))
      expect(ActiveStorage::PurgeJob).to have_been_enqueued.once
    end

    # O AGENDAMENTO DA LIMPEZA TAMBÉM FALA COM O REDIS, dentro do mesmo `ensure` (rodada 5, P3): com o
    # Redis fora no meio do job, o `perform_later` levantava por cima do resultado — a entrega que
    # JÁ estava no ar virava `blocked` e "publish failed" — e, na publicação que levantou, trocava a
    # causa dela pela do enfileiramento. A limpeza é cortesia: registrada, nunca no resultado.
    it 'mantem a entrega publicada quando a fila nao aceita a limpeza do blob do retry' do
      # Arrange — a primeira publicação saiu como anexo; o retry grava um segundo blob, acha a
      # mensagem no ar, e o Redis não aceita o job de limpeza
      promote
      stub_request(:get, url).to_return(status: 200, body: pdf, headers: { 'Content-Type' => 'application/pdf' })
      publisher = described_class.new(run: run)
      publisher.publish(arquivo.to_h)
      allow(ActiveStorage::PurgeJob).to receive(:perform_later).and_raise(Errno::ECONNREFUSED)
      allow(Rails.logger).to receive(:warn).and_call_original

      # Act
      result = publisher.publish(arquivo.to_h)

      # Assert — publicado, uma mensagem só, nada de "publish failed"; o blob sem dono fica
      # registrado (com o id, para a limpeza manual) em vez de custar a entrega
      expect(result).to be_published
      expect(bot_messages.count).to eq(1)
      expect(Rails.logger).not_to have_received(:warn).with(a_string_matching(/publish failed/))
      expect(Rails.logger).to have_received(:warn)
        .with(a_string_matching(/blob sem dono nao agendado run=#{run.id} blob=\d+ causa=Errno::ECONNREFUSED/))
      expect(ActiveStorage::Blob.count).to eq(2)
    end

    it 'registra a causa da publicacao que levantou tambem quando a fila nao aceita a limpeza' do
      # Arrange — download bom, mensagem que não nasce, Redis que não aceita o job de limpeza
      promote
      stub_request(:get, url).to_return(status: 200, body: pdf, headers: { 'Content-Type' => 'application/pdf' })
      allow(Messages::MessageBuilder).to receive(:new).and_raise(ActiveRecord::ConnectionTimeoutError)
      allow(ActiveStorage::PurgeJob).to receive(:perform_later).and_raise(Errno::ECONNREFUSED)
      allow(Rails.logger).to receive(:warn).and_call_original

      # Act
      result = described_class.new(run: run).publish(arquivo.to_h)

      # Assert — a causa no log é a da publicação, e a do agendamento tem a linha dela
      expect(result).to be_blocked
      expect(bot_messages.count).to eq(0)
      expect(Rails.logger).to have_received(:warn)
        .with(a_string_matching(/publish failed run=#{run.id} ActiveRecord::ConnectionTimeoutError/))
      expect(Rails.logger).to have_received(:warn)
        .with(a_string_matching(/blob sem dono nao agendado run=#{run.id} blob=\d+ causa=Errno::ECONNREFUSED/))
    end

    # O QUE NÃO É TEXTO NEM ARQUIVO NÃO VIRA MENSAGEM. O encerramento (`closing_deliveries`) não passa
    # pelo `Progress`, então a guarda tem de existir onde a mensagem é criada: um Hash inválido
    # chegava ao cliente como `{"arquivo" => {...}}` literal (rodada 2, P2).
    it 'descarta, registrado e sem mensagem, um Hash que nao e entrega de arquivo' do
      # Arrange
      promote
      allow(Rails.logger).to receive(:warn).and_call_original

      # Act
      qualquer = described_class.new(run: run).publish({ 'quote_id' => 'abc:1' })
      forma_invalida = described_class.new(run: run).publish(arquivo.to_h.deep_merge('arquivo' => { 'url' => 'http://inseguro.test/x.pdf' }))

      # Assert
      expect(qualquer).to be_skipped
      expect(forma_invalida).to be_skipped
      expect(bot_messages.count).to eq(0)
      expect(run.reload.sequence).to eq(0)
      expect(Rails.logger).to have_received(:warn)
        .with(a_string_matching(/entrega descartada run=#{run.id}: não é texto nem arquivo \(Hash\)/)).twice
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

    # A FALHA DO ANEXO, DEPOIS DE UM DOWNLOAD BOM (rodada 3, P2). O ActiveStorage subia o arquivo
    # no `after_commit` da mensagem: com o armazenamento fora, a mensagem já estava no ar com a
    # legenda, um anexo sem bytes e o token publicado — o cliente sem arquivo e sem link, e o retry
    # virando duplicado. Agora a gravação acontece ANTES da mensagem, dentro da mesma fronteira de
    # reserva do download: o link vai como ia antes, registrado.
    it 'cai para o texto com o link quando o armazenamento falha depois do download, sem anexo orfao' do
      # Arrange
      promote
      stub_request(:get, url).to_return(status: 200, body: pdf, headers: { 'Content-Type' => 'application/pdf' })
      allow(ActiveStorage::Blob.service).to receive(:upload).and_raise(Errno::ECONNREFUSED)
      allow(Rails.logger).to receive(:warn).and_call_original

      # Act
      result = described_class.new(run: run).publish(arquivo.to_h)

      # Assert — a linha do blob sem arquivo (salva antes da subida, rodada 6) vai para a limpeza
      expect(result).to be_published
      mensagem = bot_messages.sole
      expect(mensagem.content).to eq("Comparativo com todas as opções:\n#{url}")
      expect(mensagem.attachments).to be_empty
      expect(mensagem.content_attributes['autonomia_async_token']).to eq(run.delivery_token(arquivo.identidade))
      expect(Rails.logger).to have_received(:warn)
        .with(a_string_matching(/arquivo indisponivel run=#{run.id} motivo=armazenamento causa=Errno::ECONNREFUSED; vai como link/))
      expect(ActiveStorage::PurgeJob).to have_been_enqueued.once
      perform_enqueued_jobs(only: ActiveStorage::PurgeJob)
      expect(ActiveStorage::Blob.count).to eq(0)
    end

    # O MOTIVO É FECHADO: o cabeçalho que desmente o PDF é do servidor, e nada dele vai ao log —
    # antes saía `tipo_text_html`, com o valor externo dentro do código (rodada 6, 11/09/2026).
    it 'cai para o texto com o link quando o tipo declarado desmente o PDF, sem o cabecalho no log' do
      # Arrange
      promote
      stub_request(:get, url).to_return(status: 200, body: pdf, headers: { 'Content-Type' => 'text/html; charset=utf-8' })
      allow(Rails.logger).to receive(:warn).and_call_original

      # Act
      result = described_class.new(run: run).publish(arquivo.to_h)

      # Assert
      expect(result).to be_published
      expect(bot_messages.sole.content).to eq("Comparativo com todas as opções:\n#{url}")
      expect(Rails.logger).to have_received(:warn)
        .with(a_string_matching(/arquivo indisponivel run=#{run.id} motivo=tipo_invalido; vai como link/))
      expect(Rails.logger).not_to have_received(:warn).with(a_string_matching(%r{text/html|text_html|charset}))
    end

    # A FALHA AO ANEXAR, depois de um download e uma gravação bons (rodada 6, 11/09/2026): a mensagem
    # com o anexo não nasce (a transação volta) e, sem esta guarda, a exceção saía do publicador como
    # `blocked` — nem arquivo nem link. Agora a reserva vai com o MESMO token, registrada com a classe
    # da causa, e o blob que ficou sem dono vai para a limpeza.
    it 'cai para o texto com o link quando o anexo nao pode ser publicado, com um so token e o blob na limpeza' do
      # Arrange — a mensagem com anexo é inválida; a sem anexo (a reserva) nasce normalmente
      promote
      stub_request(:get, url).to_return(status: 200, body: pdf, headers: { 'Content-Type' => 'application/pdf' })
      allow(Messages::MessageBuilder).to receive(:new).and_wrap_original do |original, *args|
        raise ActiveRecord::RecordInvalid if args.last[:attachments].present?

        original.call(*args)
      end
      allow(Rails.logger).to receive(:warn).and_call_original

      # Act
      result = described_class.new(run: run).publish(arquivo.to_h)

      # Assert
      expect(result).to be_published
      mensagem = bot_messages.sole
      expect(mensagem.content).to eq("Comparativo com todas as opções:\n#{url}")
      expect(mensagem.attachments).to be_empty
      expect(mensagem.content_attributes['autonomia_async_token']).to eq(run.delivery_token(arquivo.identidade))
      expect(Rails.logger).to have_received(:warn)
        .with(a_string_matching(/anexo falhou run=#{run.id} causa=ActiveRecord::RecordInvalid; vai como link/))
      expect(ActiveStorage::PurgeJob).to have_been_enqueued.once
    end

    # A EXCEÇÃO DEPOIS DO COMMIT (rodada 6, P3): um callback `after_commit` da mensagem — o evento que
    # vai ao Redis — levanta com a mensagem e o anexo JÁ no ar. Sem reconciliar pelo token, a reserva
    # sairia por cima (duplicando a entrega) ou o blob anexado iria para a limpeza (a mensagem no ar
    # sem arquivo). A publicação é `published` sem mensagem nova, e o anexo fica.
    it 'mantem a mensagem com o anexo, sem reserva e sem limpeza, quando a publicacao levanta depois do commit' do
      # Arrange — o Redis cai no despacho do evento de criação da mensagem com anexo
      promote
      stub_request(:get, url).to_return(status: 200, body: pdf, headers: { 'Content-Type' => 'application/pdf' })
      allow(Rails.configuration.dispatcher).to receive(:dispatch).and_wrap_original do |original, evento, *resto|
        dados = resto[1]
        raise Redis::CannotConnectError, 'redis fora' if evento == Events::Types::MESSAGE_CREATED && dados[:message].attachments.any?

        original.call(evento, *resto)
      end
      allow(Rails.logger).to receive(:warn).and_call_original

      # Act
      result = described_class.new(run: run).publish(arquivo.to_h)

      # Assert
      expect(result).to be_published
      expect(result.message).to be_nil
      mensagem = bot_messages.sole
      expect(mensagem.content).to eq('Comparativo com todas as opções.')
      expect(mensagem.attachments.sole.file.download).to eq(pdf)
      expect(run.reload.sequence).to eq(1)
      expect(ActiveStorage::PurgeJob).not_to have_been_enqueued
      expect(Rails.logger).not_to have_received(:warn).with(a_string_matching(/publish failed|anexo falhou/))
    end

    # O DOWNLOAD E A GRAVAÇÃO ACONTECEM FORA DO LOCK DA CONVERSA: são rede e armazenamento, com prazo
    # total de 20 s, e a conversa não pode ficar travada por isso. O que se observa é a ORDEM: o
    # download começa, o arquivo sobe, e só então sai o `FOR UPDATE` da publicação (rodadas 3 e 6).
    it 'baixa e grava o arquivo antes de travar a conversa' do
      # Arrange
      promote
      stub_request(:get, url).to_return(status: 200, body: pdf, headers: { 'Content-Type' => 'application/pdf' })
      eventos = []
      assinatura = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
        eventos << :trava if payload[:sql].to_s.include?('FOR UPDATE')
      end
      allow(SafeFetch).to receive(:fetch).and_wrap_original do |original, *args, **opcoes, &bloco|
        eventos << :download
        original.call(*args, **opcoes, &bloco)
      end
      allow(ActiveStorage::Blob.service).to receive(:upload).and_wrap_original do |original, *args, **opcoes|
        eventos << :gravacao
        original.call(*args, **opcoes)
      end

      # Act
      result = described_class.new(run: run).publish(arquivo.to_h)

      # Assert — download, gravação, e só então a trava
      expect(result).to be_published
      expect(bot_messages.sole.attachments.sole.file.download).to eq(pdf)
      expect(eventos.first(3)).to eq(%i[download gravacao trava])
    ensure
      ActiveSupport::Notifications.unsubscribe(assinatura) if assinatura
    end
  end
end
