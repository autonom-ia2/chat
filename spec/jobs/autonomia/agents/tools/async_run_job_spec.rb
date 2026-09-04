require 'rails_helper'

# MOTOR da ferramenta assíncrona (#313). O critério da issue é um só: "uma tool que demora 60s
# responde na conversa sem travar worker e sem duplicar mensagem". Cada exemplo cobre um failure
# mode desse desenho — submeter sem segurar o worker, entregar parcial e final em ordem, avisar
# quando o turno ficou em silêncio, desistir no prazo, e NUNCA deixar texto de exceção chegar ao
# cliente.
RSpec.describe Autonomia::Agents::Tools::AsyncRunJob, type: :job do
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

  def progress
    Autonomia::Agents::Tools::Progress
  end

  def async_config
    Autonomia::Agents::Tools::AsyncConfig
  end

  # Execução já promovida a `running`, como o Responder faz no fim do turno.
  def create_run(notify_customer: false, expires_at: 3.minutes.from_now)
    run = Autonomia::Agents::ToolRun.open!(agent: agent, slug: 'consultar_cotacao',
                                           arguments: { 'placa' => 'ABC1D23' },
                                           scope: { conversation_id: conversation.id,
                                                    agent_inbox_id: agent_inbox.id })
    run.promote!(expected_chunks: 0, notify_customer: notify_customer,
                 expires_at: expires_at)
    run
  end

  # A 1ª execução é a SUBMISSÃO; quem já tem handle vai direto para a consulta.
  def submitted_run(notify_customer: false, expires_at: 3.minutes.from_now)
    run = create_run(notify_customer: notify_customer, expires_at: expires_at)
    # A marca `autonomia_submitted` é o que diz "já submeti" — não o conteúdo do handle. Sem ela o
    # job submeteria de novo (uma cotação real a mais no portal a cada passada).
    run.record_attempt!(handle: { Autonomia::Agents::Tools::AsyncRunJob::SUBMITTED_KEY => true,
                                  'id' => 'cot-1' })
    run
  end

  def bot_messages
    conversation.messages.reload.where(sender_type: 'AgentBot').order(:id)
  end

  def bot_contents
    bot_messages.map(&:content)
  end

  def async_attribute(key)
    bot_messages.map { |message| message.content_attributes.to_h[key] }
  end

  describe 'submission pass' do
    it 'stores the handle, publishes nothing and reschedules itself with the wait in the scheduler' do
      # Arrange
      register_async_tool(build_async_tool(handle: { 'id' => 'cot-1' }, poll: progress.running))
      run = create_run

      # Act
      described_class.new.perform(run.id, 0)

      # Assert — nada publicado ainda, handle gravado na linha, e o job volta agendado para depois:
      # a espera vive no AGENDADOR (`at` no futuro), nunca dentro do worker.
      expect(described_class).to have_been_enqueued.with(run.id, 1)
      expect(run.reload).to have_attributes(
        status: 'running',
        handle: { described_class::SUBMITTED_KEY => true, 'id' => 'cot-1' }
      )
      expect(bot_messages).to be_empty
      scheduled = enqueued_jobs.find { |job| job[:job] == described_class }
      expect(scheduled[:at]).to be_within(2).of(async_config.interval_for(agent, 0).from_now.to_f)
    end
  end

  describe 'polling passes' do
    it 'publishes a partial delivery and keeps polling' do
      # Arrange
      register_async_tool(build_async_tool(poll: progress.running(deliveries: ['parcial'])))
      run = submitted_run

      # Act
      described_class.new.perform(run.id, 1)

      # Assert
      expect(described_class).to have_been_enqueued.with(run.id, 2)
      expect(bot_contents).to eq(['parcial'])
      expect(run.reload).to have_attributes(status: 'running', sequence: 1)
    end

    it 'publishes the final delivery and closes the run as done' do
      # Arrange
      register_async_tool(build_async_tool(poll: progress.done(deliveries: ['final'])))
      run = submitted_run

      # Act
      described_class.new.perform(run.id, 1)

      # Assert
      expect(bot_contents).to eq(['final'])
      expect(run.reload).to have_attributes(status: 'done', failure_code: nil)
    end

    it 'delivers the partial and then the final as two distinct messages, in order, with sequence tokens 0 and 1' do
      # Arrange — parcial nas primeiras consultas, final depois.
      poll = ->(attempt) { attempt < 2 ? progress.running(deliveries: ['parcial']) : progress.done(deliveries: ['final']) }
      register_async_tool(build_async_tool(poll: poll))
      run = create_run

      # Act — submissão, consulta com parcial, consulta final.
      described_class.new.perform(run.id, 0)
      described_class.new.perform(run.id, 1)
      described_class.new.perform(run.id, 2)

      # Assert
      expect(bot_contents).to eq(%w[parcial final])
      expect(async_attribute('autonomia_async_token')).to eq([run.delivery_token(0), run.delivery_token(1)])
      expect(async_attribute('autonomia_async_sequence')).to eq([0, 1])
      expect(run.reload).to have_attributes(status: 'done', sequence: 2)
    end

    it 'publishes our own failure text and records the failure code when the tool reports a failure' do
      # Arrange
      register_async_tool(build_async_tool(poll: progress.failed('portal_indisponivel')))
      run = submitted_run

      # Act
      described_class.new.perform(run.id, 1)

      # Assert
      expect(bot_contents).to eq(['não consegui concluir a consulta'])
      expect(run.reload).to have_attributes(status: 'failed', failure_code: 'portal_indisponivel')
    end
  end

  describe 'waiting notice' do
    it 'publishes the waiting message on the very first pass when the turn stayed silent' do
      # Arrange
      register_async_tool(build_async_tool(poll: progress.done(deliveries: ['final'])))
      run = create_run(notify_customer: true)

      # Act / Assert — o aviso vem ANTES de qualquer outra coisa (a submissão nem publica).
      described_class.new.perform(run.id, 0)
      expect(bot_contents).to eq(['estou consultando agora'])

      described_class.new.perform(run.id, 1)
      expect(bot_contents).to eq(['estou consultando agora', 'final'])
    end

    it 'stays quiet when the turn already told the customer' do
      # Arrange
      register_async_tool(build_async_tool(poll: progress.done(deliveries: ['final'])))
      run = create_run(notify_customer: false)

      # Act
      described_class.new.perform(run.id, 0)

      # Assert
      expect(bot_messages).to be_empty
    end
  end

  describe 'giving up' do
    it 'gives up with our failure text when the wall-clock deadline is already past' do
      # Arrange
      register_async_tool(build_async_tool(poll: progress.done(deliveries: ['final'])))
      run = create_run(expires_at: 1.minute.ago)

      # Act
      described_class.new.perform(run.id, 0)

      # Assert
      expect(described_class).not_to have_been_enqueued
      expect(bot_contents).to eq(['não consegui concluir a consulta'])
      expect(run.reload).to have_attributes(status: 'failed', failure_code: 'prazo_esgotado')
    end

    it 'gives up when the attempt ceiling is reached, even inside the deadline' do
      # Arrange
      register_async_tool(build_async_tool(poll: progress.done(deliveries: ['final'])))
      run = submitted_run

      # Act
      described_class.new.perform(run.id, async_config::MAX_ATTEMPTS)

      # Assert
      expect(described_class).not_to have_been_enqueued
      expect(bot_contents).to eq(['não consegui concluir a consulta'])
      expect(run.reload).to have_attributes(status: 'failed', failure_code: 'prazo_esgotado')
    end

    it 'fails without publishing anything when the tool is gone from the catalog' do
      # Arrange — a nativa saiu do Registry entre o disparo e a execução.
      allow(Autonomia::Agents::Tools::Registry).to receive(:find).and_return(nil)
      run = create_run

      # Act
      described_class.new.perform(run.id, 0)

      # Assert — sem ferramenta não há texto NOSSO para publicar; a linha fecha em silêncio.
      expect(bot_messages).to be_empty
      expect(run.reload).to have_attributes(status: 'failed', failure_code: 'ferramenta_indisponivel')
    end
  end

  describe 'exception containment' do
    it 'swallows a poll exception, retries inside the deadline and never echoes the message' do
      # Arrange
      register_async_tool(build_async_tool(poll_error: StandardError.new('segredo-do-portal')))
      run = submitted_run

      # Act / Assert — a exceção NÃO sobe do job (subir faria o Sidekiq recotar do zero).
      expect { described_class.new.perform(run.id, 1) }.not_to raise_error

      expect(described_class).to have_been_enqueued.with(run.id, 2)
      expect(run.reload.status).to eq('running')
      expect(bot_contents.join(' ')).not_to include('segredo')
    end

    it 'keeps the exception text out of the conversation when the retry ceiling ends the run' do
      # Arrange — última tentativa possível: a falha vira desfecho, não nova tentativa.
      register_async_tool(build_async_tool(poll_error: StandardError.new('segredo-do-portal')))
      run = submitted_run

      # Act
      expect { described_class.new.perform(run.id, async_config::MAX_ATTEMPTS - 1) }.not_to raise_error

      # Assert — o cliente lê a NOSSA frase, nunca a da exceção.
      expect(bot_contents).to eq(['não consegui concluir a consulta'])
      expect(bot_contents.join(' ')).not_to include('segredo')
      expect(run.reload).to have_attributes(status: 'failed', failure_code: 'tool_failed')
    end

    it 'swallows a start exception on the submission pass' do
      # Arrange
      register_async_tool(build_async_tool(start_error: StandardError.new('segredo-do-portal')))
      run = create_run

      # Act / Assert
      expect { described_class.new.perform(run.id, 0) }.not_to raise_error

      expect(described_class).to have_been_enqueued.with(run.id, 1)
      expect(run.reload).to have_attributes(status: 'running', handle: {})
      expect(bot_messages).to be_empty
    end
  end

  describe 'no-op and idempotency' do
    it 'does nothing for a run that already finished or does not exist' do
      # Arrange
      register_async_tool(build_async_tool(poll: progress.done(deliveries: ['final'])))
      run = submitted_run
      run.finish!('done')

      # Act / Assert
      expect { described_class.new.perform(run.id, 1) }.not_to raise_error
      expect { described_class.new.perform(-1, 0) }.not_to raise_error

      expect(described_class).not_to have_been_enqueued
      expect(bot_messages).to be_empty
      expect(run.reload.status).to eq('done')
    end

    it 'does not duplicate the published delivery when the same attempt runs twice' do
      # Arrange
      register_async_tool(build_async_tool(poll: progress.done(deliveries: ['final'])))
      run = submitted_run

      # Act / Assert — 1ª execução publica.
      described_class.new.perform(run.id, 1)
      expect(bot_contents).to eq(['final'])

      # O retry do Sidekiq reexecuta o MESMO job: o guarda de status barra.
      described_class.new.perform(run.id, 1)
      expect(bot_contents).to eq(['final'])

      # E mesmo forçando a linha de volta a `running` com a sequência ainda em 0 (o job morreu depois
      # de postar e antes de avançar), é o token da entrega que impede a segunda mensagem.
      run.update_columns(status: 'running', sequence: 0) # rubocop:disable Rails/SkipsModelValidations
      described_class.new.perform(run.id, 1)
      expect(bot_contents).to eq(['final'])
    end
  end

  # O critério da issue, ponta a ponta: uma ferramenta que só conclui depois de 60 SEGUNDOS de
  # relógio é atendida por várias execuções curtas, cada uma devolvendo o worker na hora. O tempo
  # todo passa entre as execuções (no agendador), nunca dentro de uma delas.
  describe 'a 60-second tool' do
    it 'answers in the conversation without ever holding a worker and without duplicating the message' do
      # Arrange
      started = Time.current
      poll = lambda do |_attempt|
        Time.current - started >= 60 ? progress.done(deliveries: ['3 opções encontradas']) : progress.running
      end
      register_async_tool(build_async_tool(poll: poll))
      run = create_run(expires_at: 10.minutes.from_now)

      # Act — o relógio só anda ENTRE as execuções; nenhuma delas dorme.
      attempt = 0
      waited = 0.seconds
      while run.reload.running? && attempt < async_config::MAX_ATTEMPTS
        started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        described_class.new.perform(run.id, attempt)
        expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at).to be < 5
        wait = async_config.interval_for(agent, attempt)
        waited += wait
        travel(wait)
        attempt += 1
      end

      # Assert — UMA mensagem, depois de mais de 60s de espera fora do worker.
      expect(waited).to be >= 60
      expect(bot_contents).to eq(['3 opções encontradas'])
      expect(run.reload.status).to eq('done')
    end
  end
end
