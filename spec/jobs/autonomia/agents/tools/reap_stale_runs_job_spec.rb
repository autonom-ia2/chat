require 'rails_helper'

# O varredor existe porque a execução assíncrona avança por uma corrente de jobs que se re-agendam.
# Quando a corrente se rompe (worker morto num deploy, enqueue perdido com o Redis fora), ninguém
# mais olha para a linha — e o cliente fica esperando uma cotação que não vai acontecer.
RSpec.describe Autonomia::Agents::Tools::ReapStaleRunsJob, type: :job do
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

  around { |example| with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { example.run } }

  def open_run(origin_message_id: nil)
    Autonomia::Agents::ToolRun.open!(agent: agent, slug: 'consultar_cotacao', arguments: {},
                                     scope: { conversation_id: conversation.id,
                                              agent_inbox_id: agent_inbox.id,
                                              origin_message_id: origin_message_id })
  end

  def bot_contents
    conversation.reload.messages.where(sender_type: 'AgentBot').order(:id).map(&:content)
  end

  it 'closes an abandoned run and tells the customer, instead of leaving it waiting forever' do
    # Arrange — execução viva cujo prazo venceu com folga e cujo job nunca mais rodou
    register_async_tool(build_async_tool)
    run = open_run
    run.promote!(expected_chunks: 0, notify_customer: false, expires_at: 10.minutes.ago)

    # Act
    described_class.new.perform

    # Assert
    expect(run.reload).to have_attributes(status: 'failed', failure_code: 'execucao_abandonada')
    expect(bot_contents).to eq(['não consegui concluir a consulta'])
  end

  # QUEM JÁ RECEBEU ALGO LÊ O FECHO PARCIAL, não o silêncio nem "não consegui" (rodada 5 da entrega
  # 8). Antes o varredor calava aqui. Ele passou a fechar pelo MESMO `Tools::Encerramento` do motor —
  # que é o que faz o arquivo já pronto sair por este caminho —, e um fecho tinha de vir junto:
  # entregar um arquivo e não dizer nada é o defeito ao contrário. A frase não contradiz o que o
  # cliente leu; dizer "não consegui" é que contradiria.
  it 'fecha com a frase parcial quando o cliente ja recebeu uma entrega' do
    # Arrange
    tool = register_async_tool(build_async_tool)
    run = open_run
    run.promote!(expected_chunks: 0, notify_customer: false, expires_at: 10.minutes.ago)
    run.record_delivery!

    # Act
    described_class.new.perform

    # Assert
    expect(run.reload.status).to eq('failed')
    expect(bot_contents).to eq([tool.partial_message])
    expect(bot_contents.join(' ')).not_to include('não consegui')
  end

  # O VARREDOR OFERECE O ENCERRAMENTO À FERRAMENTA (rodada 5, P2). Ele fecha a linha quando a corrente
  # de jobs se rompe — e, até 12/09/2026, fechava publicando só a frase de falha: o que a ferramenta
  # ainda tinha para entregar (a proposta que o portal JÁ gerou, o comparativo da cotação) morria no
  # handle, e o cliente lia "não consegui" ao lado de um arquivo que existia. Era o defeito P2 da
  # rodada 3 vivo na outra porta, fora do alcance da correção de lá — o varredor não passa por
  # `fail_run`. A ordem importa: primeiro o que vale entregar, depois o fecho.
  it 'entrega o que a ferramenta ainda tinha antes de publicar o fecho' do
    # Arrange
    tool = register_async_tool(build_async_tool(closing: ['o arquivo que ficou pronto']))
    run = open_run
    run.promote!(expected_chunks: 0, notify_customer: false, expires_at: 10.minutes.ago)

    # Act
    described_class.new.perform

    # Assert — o arquivo primeiro, o fecho parcial depois (algo chegou agora)
    expect(bot_contents).to eq(['o arquivo que ficou pronto', tool.partial_message])
    expect(run.reload).to have_attributes(status: 'failed', failure_code: 'execucao_abandonada')
  end

  it 'leaves a run alone while it is still within its deadline plus the grace window' do
    # Arrange
    register_async_tool(build_async_tool)
    run = open_run
    run.promote!(expected_chunks: 0, notify_customer: false, expires_at: 1.minute.ago)

    # Act
    described_class.new.perform

    # Assert — venceu, mas ainda dentro da folga: um poll legítimo pode estar prestes a rodar
    expect(run.reload.status).to eq('running')
  end

  it 'discards a pending run that no dispatcher ever picked up, without talking to the customer' do
    # Arrange — o worker morreu entre o aceite e o despacho
    run = open_run
    run.update!(created_at: 2.hours.ago)

    # Act
    described_class.new.perform

    # Assert
    expect(run.reload.status).to eq('discarded')
    expect(bot_contents).to be_empty
  end

  # O BLOB SEM DONO DA ENTREGA DE ARQUIVO (rodada 7 da entrega 11, P2 do Codex): a linha do blob é
  # salva ANTES da mensagem, e o processo pode morrer entre uma e a outra — ninguém agenda a limpeza,
  # e a linha (com ou sem arquivo) fica para sempre. O varredor apaga o que tem a MARCA da entrega, está
  # sem anexo e é velho o bastante para não ser um upload em andamento. Nada fora disso é tocado: os
  # blobs dos outros caminhos do Chatwoot não são nossos para apagar.
  describe 'blobs sem dono da entrega de arquivo' do
    def blob(criado_ha:, metadata: Autonomia::Agents::Tools::EntregaDeArquivo.marca(run_id: 7))
      ActiveStorage::Blob.create_and_upload!(io: StringIO.new("%PDF-1.4\n"), filename: 'comparativo.pdf',
                                             content_type: 'application/pdf', identify: false, metadata: metadata)
                         .tap { |b| b.update!(created_at: criado_ha.ago) }
    end

    def anexar(blob)
      mensagem = create(:message, account: account, conversation: conversation, message_type: :outgoing, sender: agent_bot)
      mensagem.attachments.create!(account_id: account.id, file_type: :file).file.attach(blob)
    end

    it 'apaga o blob marcado, velho e sem anexo — e so ele' do
      # Arrange
      sem_dono = blob(criado_ha: 2.hours)
      recente = blob(criado_ha: 10.minutes)
      de_outro_caminho = blob(criado_ha: 2.hours, metadata: {})
      anexado = blob(criado_ha: 2.hours)
      anexar(anexado)

      # Act
      described_class.new.perform

      # Assert — UM agendamento (o do blob sem dono): o anexado não é nem tentado — a FK do Rails
      # barraria o `purge`, mas a guarda nossa é não pedir o que não é nosso para apagar
      expect(ActiveStorage::PurgeJob).to have_been_enqueued.once
      perform_enqueued_jobs(only: ActiveStorage::PurgeJob)
      expect(ActiveStorage::Blob.where(id: sem_dono.id)).not_to exist
      expect(ActiveStorage::Blob.where(id: [recente.id, de_outro_caminho.id, anexado.id]).count).to eq(3)
    end

    # A MARCA É LIDA COMO JSON, NO NÍVEL SUPERIOR, COM AS DUAS CHAVES (rodada 8, P2 do Codex): o `LIKE`
    # sobre o texto tratava `_` como curinga (`entrega_de_arquivo` casava `entregaXdeXarquivo`), casava
    # a marca ANINHADA em outro objeto, e não exigia o id da execução — três jeitos de escolher um blob
    # alheio ainda sem anexo. O id tem de ser um NÚMERO (rodada 9): `{"autonomia_tool_run_id": null}`
    # tem a chave e não é marca nossa. E `metadata` é `text`: uma linha que não seja JSON não pode
    # derrubar a varredura (o cast só acontece para o que É objeto JSON).
    it 'nao apaga o que so PARECE marcado: curinga do LIKE, marca aninhada, marca sem execucao ou com execucao nula, texto que nao e JSON' do
      # Arrange — um blob nosso e cinco impostores, todos velhos e sem anexo
      sem_dono = blob(criado_ha: 2.hours)
      curinga = blob(criado_ha: 2.hours, metadata: { 'autonomiaXfinalidade' => 'entregaXdeXarquivo', 'autonomia_tool_run_id' => 7 })
      aninhada = blob(criado_ha: 2.hours, metadata: { 'origem' => Autonomia::Agents::Tools::EntregaDeArquivo.marca(run_id: 7) })
      sem_execucao = blob(criado_ha: 2.hours, metadata: { 'autonomia_finalidade' => 'entrega_de_arquivo' })
      execucao_nula = blob(criado_ha: 2.hours, metadata: { 'autonomia_finalidade' => 'entrega_de_arquivo', 'autonomia_tool_run_id' => nil })
      nao_json = blob(criado_ha: 2.hours)
      ActiveStorage::Blob.where(id: nao_json.id).update_all("metadata = 'nao e json'") # rubocop:disable Rails/SkipsModelValidations

      # Act
      described_class.new.perform

      # Assert
      expect(ActiveStorage::PurgeJob).to have_been_enqueued.once
      perform_enqueued_jobs(only: ActiveStorage::PurgeJob)
      expect(ActiveStorage::Blob.where(id: sem_dono.id)).not_to exist
      expect(ActiveStorage::Blob.where(id: [curinga.id, aninhada.id, sem_execucao.id, execucao_nula.id, nao_json.id]).count).to eq(5)
    end

    # A limpeza é cortesia (rodadas 4 e 5): o Redis fora no agendamento fica registrado, com o id do
    # blob, e não derruba o resto da varredura.
    it 'registra o blob que a fila nao aceitou, sem derrubar a varredura' do
      # Arrange
      sem_dono = blob(criado_ha: 2.hours)
      allow(ActiveStorage::PurgeJob).to receive(:perform_later).and_raise(Redis::CannotConnectError)
      allow(Rails.logger).to receive(:warn).and_call_original

      # Act / Assert
      expect { described_class.new.perform }.not_to raise_error
      expect(Rails.logger).to have_received(:warn)
        .with(a_string_matching(/blob sem dono nao agendado varredor blob=#{sem_dono.id} causa=Redis::CannotConnectError/))
    end
  end

  # A MENSAGEM COM ENVIO PENDENTE (rodada 9 da entrega 11, P2 do Codex): o publicador a deixou no banco
  # com a marca porque o `SendReplyJob` não entrou na fila (o Redis fora), e NINGUÉM a reemite — o
  # `AsyncRunJob` encerra, `comparativo_enviado` impede nova emissão do PDF, o Redis voltar não dispara
  # nada. O varredor é o recuperador durável: pelo JOB inteiro, a mensagem marcada com a fila de volta
  # vira exatamente UM `SendReplyJob` e a marca sai; a execução que morreu não envia nada, a marca sai
  # e o motivo fica no log. A mensagem é criada pelo publicador de verdade, com a fila recusando o envio.
  describe 'envios pendentes' do
    let(:run) { open_run.tap { |r| r.promote!(expected_chunks: 0, notify_customer: false, expires_at: 3.minutes.from_now) } }
    let(:publisher) { Autonomia::Agents::Tools::AsyncPublisher.new(run: run) }

    # -> a mensagem marcada pela primeira tentativa (fila recusando o envio), com a fila já de volta.
    def mensagem_pendente
      fila_recusa_o_envio
      expect(publisher.publish('cotação pronta')).to be_blocked
      fila_volta
      conversation.messages.where(sender_type: 'AgentBot').sole.tap do |mensagem|
        expect(mensagem.content_attributes).to include('autonomia_envio_pendente' => true, 'autonomia_tool_run_id' => run.id)
      end
    end

    def marca(mensagem)
      mensagem.reload.content_attributes.slice('autonomia_envio_pendente', 'autonomia_tool_run_id')
    end

    it 'reenvia a mensagem marcada quando a fila volta, uma vez, e limpa a marca' do
      # Arrange
      mensagem = mensagem_pendente
      allow(Rails.logger).to receive(:warn).and_call_original

      # Act
      described_class.new.perform

      # Assert — um job, com o id dela; a marca e a execução saem; o token fica
      expect(SendReplyJob).to have_been_enqueued.with(mensagem.id).once
      expect(marca(mensagem)).to be_empty
      expect(mensagem.content_attributes['autonomia_async_token']).to be_present
      expect(Rails.logger).to have_received(:warn).with(a_string_matching(/envio pendente encontrado run=#{run.id} message=#{mensagem.id}/))
      expect(Rails.logger).to have_received(:warn).with(a_string_matching(/envio reenfileirado run=#{run.id} message=#{mensagem.id}/))
    end

    it 'abandona a pendencia da execucao morta: nada enviado, marca limpa, motivo registrado' do
      # Arrange — o cliente corrigiu o pedido e a execução foi substituída antes de o Redis voltar
      mensagem = mensagem_pendente
      run.update!(status: 'superseded')
      allow(Rails.logger).to receive(:warn).and_call_original

      # Act
      described_class.new.perform

      # Assert
      expect(SendReplyJob).not_to have_been_enqueued
      expect(marca(mensagem)).to be_empty
      expect(Rails.logger).to have_received(:warn)
        .with(a_string_matching(/envio pendente abandonado run=#{run.id} message=#{mensagem.id} motivo=execucao_morta/))
    end

    it 'abandona a pendencia do agente desligado, e a marca que nao aponta para execucao nenhuma' do
      # Arrange
      mensagem = mensagem_pendente
      agent.update!(enabled: false)
      sem_execucao = create(:message, account: account, conversation: conversation, message_type: :outgoing, sender: agent_bot,
                                      content_attributes: { 'autonomia_envio_pendente' => true })
      clear_enqueued_jobs # o `send_reply` da mensagem criada pela factory
      allow(Rails.logger).to receive(:warn).and_call_original

      # Act
      described_class.new.perform

      # Assert
      expect(SendReplyJob).not_to have_been_enqueued
      expect([marca(mensagem), marca(sem_execucao)]).to all(be_empty)
      expect(Rails.logger).to have_received(:warn)
        .with(a_string_matching(/envio pendente abandonado run=#{run.id} message=#{mensagem.id} motivo=vinculo_mudou/))
      expect(Rails.logger).to have_received(:warn)
        .with(a_string_matching(/envio pendente abandonado varredor message=#{sem_execucao.id} motivo=sem_execucao/))
    end

    it 'nao reenvia a marcada que o canal ja confirmou: limpa a marca com o motivo' do
      # Arrange
      mensagem = mensagem_pendente
      mensagem.update!(source_id: 'wamid.confirmado')
      allow(Rails.logger).to receive(:warn).and_call_original

      # Act
      described_class.new.perform

      # Assert
      expect(SendReplyJob).not_to have_been_enqueued
      expect(marca(mensagem)).to be_empty
      expect(Rails.logger).to have_received(:warn)
        .with(a_string_matching(/envio pendente abandonado run=#{run.id} message=#{mensagem.id} motivo=canal_confirmou/))
    end

    it 'deixa a marca e registra quando a fila continua fora' do
      # Arrange
      mensagem = mensagem_pendente
      fila_recusa_o_envio
      allow(Rails.logger).to receive(:warn).and_call_original

      # Act / Assert — nada levanta, a marca fica para a próxima passada
      expect { described_class.new.perform }.not_to raise_error
      expect(SendReplyJob).not_to have_been_enqueued
      expect(marca(mensagem)).to eq('autonomia_envio_pendente' => true, 'autonomia_tool_run_id' => run.id)
      incompleta = /publicacao incompleta run=#{run.id} message=#{mensagem.id} motivo=mensagem_sem_envio causa=Redis::CannotConnectError/
      expect(Rails.logger).to have_received(:warn).with(a_string_matching(incompleta))
    end

    # Uma retomada que levanta (o lock da conversa que não vem, o banco que cai no meio) não pode
    # derrubar as outras 199 da passada: fica registrada, a marca dela fica para a próxima, e o
    # varredor segue. Sem o `rescue`, a primeira exceção encerrava a varredura inteira — L17 sobreviveu
    # à primeira passada de mutação da rodada 9 porque nada exercitava isso.
    it 'registra a retomada que levanta e segue para as outras' do
      # Arrange — duas marcadas da mesma execução; a retomada da primeira levanta
      mensagem = mensagem_pendente
      outra = create(:message, account: account, conversation: conversation, message_type: :outgoing, sender: agent_bot,
                               content_attributes: { 'autonomia_envio_pendente' => true, 'autonomia_tool_run_id' => run.id })
      clear_enqueued_jobs # o `send_reply` da mensagem criada pela factory
      allow(Autonomia::Agents::Tools::RetomadaDeEnvio).to receive(:new).and_wrap_original do |original, **args|
        original.call(**args).tap do |retomada|
          allow(retomada).to receive(:recuperar).and_wrap_original do |recuperar, alvo|
            raise ActiveRecord::LockWaitTimeout, 'a conversa nao destravou' if alvo.id == mensagem.id

            recuperar.call(alvo)
          end
        end
      end
      allow(Rails.logger).to receive(:warn).and_call_original

      # Act / Assert — nada sobe; a outra é reenviada; a que levantou fica marcada e registrada
      expect { described_class.new.perform }.not_to raise_error
      expect(SendReplyJob).to have_been_enqueued.with(outra.id).once
      expect(marca(mensagem)).to eq('autonomia_envio_pendente' => true, 'autonomia_tool_run_id' => run.id)
      expect(Rails.logger).to have_received(:warn)
        .with(a_string_matching(/retomada de envio falhou varredor message=#{mensagem.id} ActiveRecord::LockWaitTimeout/))
    end

    it 'nao mexe na marcada fora da janela de dois dias' do
      # Arrange
      mensagem = mensagem_pendente
      mensagem.update_columns(created_at: 3.days.ago) # rubocop:disable Rails/SkipsModelValidations

      # Act
      described_class.new.perform

      # Assert
      expect(SendReplyJob).not_to have_been_enqueued
      expect(marca(mensagem)).to eq('autonomia_envio_pendente' => true, 'autonomia_tool_run_id' => run.id)
    end
  end
end
