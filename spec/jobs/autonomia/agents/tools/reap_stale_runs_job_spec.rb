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

  it 'stays silent when the customer already received a delivery' do
    # Arrange
    register_async_tool(build_async_tool)
    run = open_run
    run.promote!(expected_chunks: 0, notify_customer: false, expires_at: 10.minutes.ago)
    run.record_delivery!

    # Act
    described_class.new.perform

    # Assert — fecha a linha, mas não contradiz o que o cliente já leu
    expect(run.reload.status).to eq('failed')
    expect(bot_contents).to be_empty
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
    # alheio ainda sem anexo. E `metadata` é `text`: uma linha que não seja JSON não pode derrubar a
    # varredura (o cast só acontece para o que É objeto JSON).
    it 'nao apaga o que so PARECE marcado: curinga do LIKE, marca aninhada, marca sem execucao, texto que nao e JSON' do
      # Arrange — um blob nosso e quatro impostores, todos velhos e sem anexo
      sem_dono = blob(criado_ha: 2.hours)
      curinga = blob(criado_ha: 2.hours, metadata: { 'autonomiaXfinalidade' => 'entregaXdeXarquivo', 'autonomia_tool_run_id' => 7 })
      aninhada = blob(criado_ha: 2.hours, metadata: { 'origem' => Autonomia::Agents::Tools::EntregaDeArquivo.marca(run_id: 7) })
      sem_execucao = blob(criado_ha: 2.hours, metadata: { 'autonomia_finalidade' => 'entrega_de_arquivo' })
      nao_json = blob(criado_ha: 2.hours)
      ActiveStorage::Blob.where(id: nao_json.id).update_all("metadata = 'nao e json'") # rubocop:disable Rails/SkipsModelValidations

      # Act
      described_class.new.perform

      # Assert
      expect(ActiveStorage::PurgeJob).to have_been_enqueued.once
      perform_enqueued_jobs(only: ActiveStorage::PurgeJob)
      expect(ActiveStorage::Blob.where(id: sem_dono.id)).not_to exist
      expect(ActiveStorage::Blob.where(id: [curinga.id, aninhada.id, sem_execucao.id, nao_json.id]).count).to eq(4)
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
end
