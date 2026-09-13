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

  # A fila que recusa o `SendReplyJob` (`fila_recusa_o_envio`/`fila_volta`) mora em `spec/support/fila_de_envio_helper.rb`.
  def marca_de_pendencia(mensagem)
    mensagem.reload.content_attributes['autonomia_envio_pendente']
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

  # A RETOMADA DA PENDÊNCIA ACONTECE SOB O LOCK (rodada 9, P2 do Codex). Até a rodada 8 a tentativa
  # seguinte lia a marca sob o lock, SOLTAVA o lock e reenfileirava fora dele: duas tentativas
  # concorrentes (o retry do Sidekiq e a reemissão pelo poll) liam a marca uma depois da outra, cada uma
  # sob o seu lock, e as duas reenfileiravam — dois `SendReplyJob`, o documento duas vezes. O que estes
  # exemplos provam é a ORDEM: a mensagem é RELIDA sob o lock (um concorrente que resolveu a pendência
  # um instante antes do lock é visto), e a retomada TERMINA antes de o lock ser solto (um concorrente
  # que entra logo depois não acha pendência). O concorrente é simulado no ponto exato do lock — é o
  # lock que impede duas threads no mesmo instante, e é a ordem em torno dele que o exemplo exercita.
  describe 'retomada da pendencia sob o lock da conversa' do
    # A conversa que o publicador vai travar, com um "outro processo" agindo no instante em que o lock
    # é adquirido (`ao_entrar`), quando o bloco termina mas antes do commit (`ao_sair`) e logo depois
    # de o lock ser solto (`depois`). Só o objeto que o publicador recebe é embrulhado.
    def conversa_com_concorrente(ao_entrar: nil, ao_sair: nil, depois: nil)
      conversa = Conversation.find(conversation.id)
      allow(run).to receive(:conversation).and_return(conversa)
      allow(conversa).to receive(:with_lock).and_wrap_original do |original, *args, &bloco|
        resultado = original.call(*args) do
          ao_entrar&.call
          bloco.call.tap { ao_sair&.call }
        end
        depois&.call
        resultado
      end
    end

    # O que a OUTRA tentativa faz quando acha a pendência: reenfileira e limpa, como o publicador.
    def outra_tentativa_resolve(mensagem)
      lambda do
        atual = Message.find(mensagem.id)
        next unless Autonomia::Agents::Tools::PendenciaDeEnvio.pendente?(atual)

        SendReplyJob.perform_later(atual.id)
        Autonomia::Agents::Tools::PendenciaDeEnvio.limpar(atual, contexto: 'concorrente')
      end
    end

    # -> a mensagem marcada, deixada por uma primeira tentativa com a fila recusando o envio.
    def mensagem_pendente(publisher)
      fila_recusa_o_envio
      expect(publisher.publish('cotação pronta')).to be_blocked
      fila_volta
      bot_messages.sole.tap { |mensagem| expect(marca_de_pendencia(mensagem)).to be(true) }
    end

    it 'rele a mensagem sob o lock: a pendencia que outro resolveu um instante antes nao e reenviada' do
      # Arrange
      promote
      publisher = described_class.new(run: run)
      mensagem = mensagem_pendente(publisher)
      conversa_com_concorrente(ao_entrar: outra_tentativa_resolve(mensagem))

      # Act
      result = publisher.publish('cotação pronta')

      # Assert — UM job (o do concorrente), a marca limpa, e a entrega dada como publicada
      expect(result).to be_published
      expect(SendReplyJob).to have_been_enqueued.with(mensagem.id).once
      expect(mensagem.reload.content_attributes).not_to have_key('autonomia_envio_pendente')
      expect(bot_messages.count).to eq(1)
    end

    it 'termina a retomada antes de soltar o lock: quem entra logo depois nao acha pendencia' do
      # Arrange
      promote
      publisher = described_class.new(run: run)
      mensagem = mensagem_pendente(publisher)
      conversa_com_concorrente(depois: outra_tentativa_resolve(mensagem))

      # Act
      result = publisher.publish('cotação pronta')

      # Assert — UM job (o desta tentativa), a marca limpa
      expect(result).to be_published
      expect(SendReplyJob).to have_been_enqueued.with(mensagem.id).once
      expect(mensagem.reload.content_attributes).not_to have_key('autonomia_envio_pendente')
    end

    # O enfileiramento dentro do lock é IMEDIATO (`ActiveJob::Base.enqueue_after_transaction_commit` é
    # `:never` nesta instalação): o job está na fila ainda dentro da transação do lock. Se um dia for
    # adiado para o commit, `reenviar` diria "entrou" antes de entrar — e este exemplo reprova.
    it 'poe o reenvio na fila ainda dentro do lock, antes do commit' do
      # Arrange
      promote
      publisher = described_class.new(run: run)
      mensagem_pendente(publisher)
      na_fila_ao_sair = nil
      conversa_com_concorrente(ao_sair: -> { na_fila_ao_sair = enqueued_jobs.count { |job| job[:job] == SendReplyJob } })

      # Act
      publisher.publish('cotação pronta')

      # Assert
      expect(na_fila_ao_sair).to eq(1)
    end
  end

  # A ENTREGA DE ARQUIVO (entrega 11): o comparativo em PDF vai como ANEXO da mensagem, com o nome
  # que o cliente vai procurar depois. Quando o download falha, vai o texto de reserva com o link —
  # o mesmo de antes —, registrado, e nunca em silêncio. A identidade é uma só nos dois caminhos.
  describe 'entrega de arquivo' do
    let(:url) { 'https://arquivos.exemplo.test/comparativo-9.pdf' }
    let(:arquivo) do
      Autonomia::Agents::Tools::EntregaDeArquivo.new(url: url, nome: 'Comparativo de seguro, placa ABC1D23.pdf',
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
      expect(anexo.file.filename.to_s).to eq('Comparativo de seguro, placa ABC1D23.pdf')
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
      # feita, não sobra blob nenhum. A mensagem achada sem pendência de envio não é reenviada: o
      # único `SendReplyJob` é o do `send_reply` dela (rodada 8).
      expect(result).to be_published
      expect(bot_messages.count).to eq(1)
      expect(run.reload.sequence).to eq(1)
      expect(SendReplyJob).to have_been_enqueued.once
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

    # A EXCEÇÃO DEPOIS DO COMMIT (rodada 6, P3; rodada 7, P2): um callback `after_commit` da mensagem
    # levanta com a mensagem e o anexo JÁ no banco. A mensagem no banco NÃO é entrega: o cliente só
    # recebe quando o `send_reply` da `Message` enfileira o `SendReplyJob` — e ele vem DEPOIS do
    # despacho de eventos, que fala com o Redis. Quando o despacho levanta, o envio não foi disparado:
    # o publicador o dispara ele mesmo, uma vez, e só então a entrega é `published` — sem reserva por
    # cima (duplicaria) e sem mandar o blob anexado para a limpeza (a mensagem no ar sem arquivo).
    describe 'quando a publicacao levanta depois do commit' do
      def redis_cai_no_despacho_da_mensagem_com_anexo
        allow(Rails.configuration.dispatcher).to receive(:dispatch).and_wrap_original do |original, evento, *resto|
          dados = resto[1]
          raise Redis::CannotConnectError, 'redis fora' if evento == Events::Types::MESSAGE_CREATED && dados[:message].attachments.any?

          original.call(evento, *resto)
        end
      end

      # A PRIMEIRA tentativa, com a fila recusando o envio: `blocked`, a mensagem no banco com o anexo
      # e a pendência gravada. -> a mensagem. (Pré-condição dos exemplos da tentativa seguinte.)
      def tentativa_bloqueada(publisher)
        fila_recusa_o_envio
        expect(publisher.publish(arquivo.to_h)).to be_blocked
        bot_messages.sole.tap { |mensagem| expect(marca_de_pendencia(mensagem)).to be(true) }
      end

      it 'mantem a mensagem com o anexo e dispara o envio que o despacho impediu, uma vez' do
        # Arrange — o Redis cai no despacho do evento de criação: o `send_reply` nunca roda
        promote
        stub_request(:get, url).to_return(status: 200, body: pdf, headers: { 'Content-Type' => 'application/pdf' })
        redis_cai_no_despacho_da_mensagem_com_anexo
        allow(Rails.logger).to receive(:warn).and_call_original

        # Act
        result = described_class.new(run: run).publish(arquivo.to_h)

        # Assert
        expect(result).to be_published
        expect(result.message).to be_nil
        mensagem = bot_messages.sole
        expect(mensagem.attachments.sole.file.download).to eq(pdf)
        expect(SendReplyJob).to have_been_enqueued.with(mensagem.id).once
        expect(run.reload.sequence).to eq(1)
        expect(ActiveStorage::PurgeJob).not_to have_been_enqueued
        expect(Rails.logger).to have_received(:warn).with(a_string_matching(/envio reenfileirado run=#{run.id} message=#{mensagem.id}/))
      end

      # A exceção pode vir DEPOIS do `send_reply` (um callback posterior): aí o job já está na fila, e
      # disparar de novo seria correr contra ele — o `SendReplyJob` só é idempotente para mensagem JÁ
      # enviada (`source_id`), não para uma a caminho. O que decide é o vigia: o envio entrou na fila.
      it 'nao dispara um segundo envio quando o send_reply ja enfileirou antes da excecao' do
        # Arrange — o gancho de templates (depois do `send_reply`) levanta
        promote
        stub_request(:get, url).to_return(status: 200, body: pdf, headers: { 'Content-Type' => 'application/pdf' })
        allow(MessageTemplates::HookExecutionService).to receive(:new).and_raise(Redis::CannotConnectError, 'redis fora')
        allow(Rails.logger).to receive(:warn).and_call_original

        # Act
        result = described_class.new(run: run).publish(arquivo.to_h)

        # Assert
        expect(result).to be_published
        mensagem = bot_messages.sole
        expect(mensagem.attachments.sole.file.download).to eq(pdf)
        expect(SendReplyJob).to have_been_enqueued.with(mensagem.id).once
        expect(ActiveStorage::PurgeJob).not_to have_been_enqueued
        expect(Rails.logger).not_to have_received(:warn).with(a_string_matching(/envio reenfileirado|publish failed|anexo falhou/))
      end

      # A nota privada não vai ao canal (o `SendReplyJob` a ignora): não há envio a disparar.
      it 'nao dispara envio para a nota privada, que nao vai ao canal' do
        # Arrange
        promote
        conversation.update!(assignee: create(:user, account: account, role: :agent))
        stub_request(:get, url).to_return(status: 200, body: pdf, headers: { 'Content-Type' => 'application/pdf' })
        redis_cai_no_despacho_da_mensagem_com_anexo
        allow(Rails.logger).to receive(:warn).and_call_original

        # Act
        result = described_class.new(run: run).publish(arquivo.to_h)

        # Assert
        expect(result).to be_published
        expect(bot_messages.sole.private).to be(true)
        expect(SendReplyJob).not_to have_been_enqueued
        expect(Rails.logger).not_to have_received(:warn).with(a_string_matching(/envio reenfileirado/))
      end

      # "PUBLICADO" NO PAPEL É PROIBIDO: se nem o envio de recuperação entra na fila (o Redis continua
      # fora), a mensagem está no banco com o anexo e o cliente sem arquivo e sem link — a falha é
      # explícita (`blocked`, código fechado), o blob anexado fica, ninguém conta a entrega, e a
      # PENDÊNCIA fica gravada na mensagem para a tentativa seguinte (rodada 8).
      it 'e explicita, com codigo fechado, quando nem o envio de recuperacao entra na fila' do
        # Arrange — o Redis recusa o `SendReplyJob` (do `send_reply` e o da recuperação); o resto entra
        promote
        stub_request(:get, url).to_return(status: 200, body: pdf, headers: { 'Content-Type' => 'application/pdf' })
        fila_recusa_o_envio
        allow(Rails.logger).to receive(:warn).and_call_original

        # Act
        result = described_class.new(run: run).publish(arquivo.to_h)

        # Assert
        expect(result).to be_blocked
        mensagem = bot_messages.sole
        expect(mensagem.attachments.sole.file.download).to eq(pdf)
        expect(SendReplyJob).not_to have_been_enqueued
        expect(ActiveStorage::PurgeJob).not_to have_been_enqueued
        expect(marca_de_pendencia(mensagem)).to be(true)
        expect(mensagem.content_attributes['autonomia_async_token']).to eq(run.delivery_token(arquivo.identidade))
        incompleta = /publicacao incompleta run=#{run.id} message=#{mensagem.id} motivo=mensagem_sem_envio causa=Redis::CannotConnectError/
        expect(Rails.logger).to have_received(:warn).with(a_string_matching(incompleta))
      end

      # A PENDÊNCIA FICA NA MENSAGEM (rodada 8, P2 do Codex): sem ela, a tentativa seguinte achava o
      # token, dizia `published` e ninguém mais olhava — o cliente sem arquivo e sem link, contado como
      # entregue. Com a marca, a tentativa seguinte reenfileira o envio UMA vez e só então limpa a marca.
      it 'reenvia na tentativa seguinte o envio que ficou pendente, uma vez, e limpa a marca' do
        # Arrange — primeira tentativa com a fila recusando o envio; depois o Redis volta
        promote
        stub_request(:get, url).to_return(status: 200, body: pdf, headers: { 'Content-Type' => 'application/pdf' })
        publisher = described_class.new(run: run)
        mensagem = tentativa_bloqueada(publisher)
        fila_volta
        allow(Rails.logger).to receive(:warn).and_call_original

        # Act
        result = publisher.publish(arquivo.to_h)

        # Assert — uma mensagem, um envio, marca limpa; o blob que a tentativa gravou antes de achar a
        # mensagem vai para a limpeza (o anexado fica: uma mensagem só, com o arquivo)
        expect(result).to be_published
        expect(bot_messages.count).to eq(1)
        expect(SendReplyJob).to have_been_enqueued.with(mensagem.id).once
        expect(mensagem.reload.content_attributes).not_to have_key('autonomia_envio_pendente')
        expect(Rails.logger).to have_received(:warn).with(a_string_matching(/envio pendente encontrado run=#{run.id} message=#{mensagem.id}/))
        expect(Rails.logger).to have_received(:warn).with(a_string_matching(/envio reenfileirado run=#{run.id} message=#{mensagem.id}/))
        expect(ActiveStorage::PurgeJob).to have_been_enqueued.once
      end

      # Marcar e limpar MESCLAM: o resto do `content_attributes` (o token, a sequência) e o anexo
      # sobrevivem às duas escritas — sem isso o token sumiria e a reemissão publicaria de novo.
      it 'preserva o token, a sequencia e o anexo ao marcar e ao limpar a pendencia' do
        # Arrange
        promote
        stub_request(:get, url).to_return(status: 200, body: pdf, headers: { 'Content-Type' => 'application/pdf' })
        publisher = described_class.new(run: run)
        mensagem = tentativa_bloqueada(publisher)
        token = run.delivery_token(arquivo.identidade)
        expect(mensagem.content_attributes['autonomia_async_token']).to eq(token)
        fila_volta

        # Act
        publisher.publish(arquivo.to_h)

        # Assert
        mensagem.reload
        expect(mensagem.content_attributes).to include('autonomia_async_token' => token, 'autonomia_async_sequence' => 0)
        expect(mensagem.content_attributes).not_to have_key('autonomia_envio_pendente')
        expect(mensagem.attachments.sole.file.download).to eq(pdf)
      end

      it 'mantem a pendencia e devolve blocked de novo quando a fila continua fora na tentativa seguinte' do
        # Arrange
        promote
        stub_request(:get, url).to_return(status: 200, body: pdf, headers: { 'Content-Type' => 'application/pdf' })
        publisher = described_class.new(run: run)
        mensagem = tentativa_bloqueada(publisher)
        allow(Rails.logger).to receive(:warn).and_call_original

        # Act
        result = publisher.publish(arquivo.to_h)

        # Assert
        expect(result).to be_blocked
        expect(bot_messages.count).to eq(1)
        expect(SendReplyJob).not_to have_been_enqueued
        expect(marca_de_pendencia(mensagem)).to be(true)
        incompleta = /publicacao incompleta run=#{run.id} message=#{mensagem.id} motivo=mensagem_sem_envio causa=Redis::CannotConnectError/
        expect(Rails.logger).to have_received(:warn).with(a_string_matching(incompleta))
      end

      # `perform_later` devolve `false`, SEM exceção, quando um callback de enqueue barra ou o adapter
      # levanta `EnqueueError`: é falha como qualquer outra, com código fechado (ressalva do Codex,
      # rodada 8). Só a chamada direta é simulada: o `send_reply` da mensagem usa `set(wait:)`.
      it 'trata o enfileiramento recusado sem excecao como falha, com a pendencia gravada' do
        # Arrange — o despacho levanta (o `send_reply` não roda) e a recuperação recebe `false`
        promote
        stub_request(:get, url).to_return(status: 200, body: pdf, headers: { 'Content-Type' => 'application/pdf' })
        redis_cai_no_despacho_da_mensagem_com_anexo
        allow(SendReplyJob).to receive(:perform_later).and_return(false)
        allow(Rails.logger).to receive(:warn).and_call_original

        # Act
        result = described_class.new(run: run).publish(arquivo.to_h)

        # Assert
        expect(result).to be_blocked
        mensagem = bot_messages.sole
        expect(SendReplyJob).not_to have_been_enqueued
        expect(marca_de_pendencia(mensagem)).to be(true)
        incompleta = /publicacao incompleta run=#{run.id} message=#{mensagem.id} motivo=mensagem_sem_envio causa=enqueue_recusado/
        expect(Rails.logger).to have_received(:warn).with(a_string_matching(incompleta))
      end

      # A marca sem `source_id` vazio não é pendência: o canal já confirmou (a recuperação operacional
      # pelo id, por exemplo) e reenviar seria o documento duas vezes.
      it 'nao reenvia a mensagem marcada que o canal ja confirmou' do
        # Arrange
        promote
        stub_request(:get, url).to_return(status: 200, body: pdf, headers: { 'Content-Type' => 'application/pdf' })
        publisher = described_class.new(run: run)
        mensagem = tentativa_bloqueada(publisher)
        mensagem.update!(source_id: 'wamid.confirmado')
        fila_volta

        # Act
        result = publisher.publish(arquivo.to_h)

        # Assert
        expect(result).to be_published
        expect(bot_messages.count).to eq(1)
        expect(SendReplyJob).not_to have_been_enqueued
      end

      # Só a mensagem que ESTA publicação criou e que FICOU no banco é reconciliada: quando o COMMIT
      # falha depois de criá-la (o `before_commit` da mensagem levanta e a transação volta), ela não
      # está no banco — `persisted?` volta a ser falso no rollback —, não há envio a reconciliar, e a
      # exceção segue o caminho de sempre: a reserva com o mesmo token, e o blob sem dono na limpeza.
      it 'cai para o texto com o link quando o commit da mensagem com anexo falha depois de cria-la' do
        # Arrange — a mensagem com anexo levanta no `before_commit`; a reserva (sem anexo) passa
        promote
        stub_request(:get, url).to_return(status: 200, body: pdf, headers: { 'Content-Type' => 'application/pdf' })
        allow(Messages::MessageBuilder).to receive(:new).and_wrap_original do |original, *args|
          original.call(*args).tap do |construtor|
            allow(construtor).to receive(:perform).and_wrap_original do |perform|
              perform.call.tap do |mensagem|
                allow(mensagem).to receive(:before_committed!).and_raise(ActiveRecord::StatementInvalid, 'commit falhou') if mensagem.attachments.any?
              end
            end
          end
        end
        allow(Rails.logger).to receive(:warn).and_call_original

        # Act
        result = described_class.new(run: run).publish(arquivo.to_h)

        # Assert
        expect(result).to be_published
        mensagem = bot_messages.sole
        expect(mensagem.content).to eq("Comparativo com todas as opções:\n#{url}")
        expect(mensagem.attachments).to be_empty
        expect(SendReplyJob).to have_been_enqueued.with(mensagem.id).once
        expect(Rails.logger).to have_received(:warn)
          .with(a_string_matching(/anexo falhou run=#{run.id} causa=ActiveRecord::StatementInvalid; vai como link/))
        expect(ActiveStorage::PurgeJob).to have_been_enqueued.once
      end
    end

    # A AUTORIZAÇÃO É RECONFERIDA SOB O LOCK, sem cache, imediatamente antes de criar a mensagem
    # (rodada 7, P1): entre a conferência do começo e a mensagem há um download e uma gravação, e nesse
    # intervalo a execução pode ser supersedida, o agente desligado, a allowlist mudar. Publicar com a
    # conferência velha é falar com cliente real a partir de um agente que já foi desligado.
    describe 'quando a autorizacao cai durante a transferencia' do
      def durante_a_gravacao
        allow(ActiveStorage::Blob.service).to receive(:upload).and_wrap_original do |original, *args, **opcoes|
          yield
          original.call(*args, **opcoes)
        end
      end

      it 'nao publica o arquivo da execucao supersedida no meio do download, e manda o blob para a limpeza' do
        # Arrange — outro processo supersede a execução (o cliente corrigiu o pedido) durante a gravação
        promote
        stub_request(:get, url).to_return(status: 200, body: pdf, headers: { 'Content-Type' => 'application/pdf' })
        durante_a_gravacao { Autonomia::Agents::ToolRun.where(id: run.id).update_all(status: 'superseded') } # rubocop:disable Rails/SkipsModelValidations
        allow(Rails.logger).to receive(:warn).and_call_original

        # Act
        result = described_class.new(run: run).publish(arquivo.to_h)

        # Assert
        expect(result).to be_blocked
        expect(bot_messages).to be_empty
        expect(run.reload.sequence).to eq(0)
        expect(Rails.logger).to have_received(:warn).with(a_string_matching(/publicacao recusada run=#{run.id} motivo=execucao_morta/))
        expect(ActiveStorage::PurgeJob).to have_been_enqueued.once
      end

      it 'nao publica o arquivo do agente desligado no meio do download, e manda o blob para a limpeza' do
        # Arrange — o operador desliga o agente durante a gravação
        promote
        stub_request(:get, url).to_return(status: 200, body: pdf, headers: { 'Content-Type' => 'application/pdf' })
        durante_a_gravacao { agent.update!(enabled: false) }
        allow(Rails.logger).to receive(:warn).and_call_original

        # Act
        result = described_class.new(run: run).publish(arquivo.to_h)

        # Assert
        expect(result).to be_blocked
        expect(bot_messages).to be_empty
        expect(run.reload.sequence).to eq(0)
        expect(Rails.logger).to have_received(:warn).with(a_string_matching(/publicacao recusada run=#{run.id} motivo=vinculo_mudou/))
        expect(ActiveStorage::PurgeJob).to have_been_enqueued.once
      end
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
