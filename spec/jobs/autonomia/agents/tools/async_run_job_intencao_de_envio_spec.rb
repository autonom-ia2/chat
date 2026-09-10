require 'rails_helper'

# A ORDEM QUE PROTEGE O DINHEIRO (entrega 5). O job anota a INTENÇÃO de submeter antes de chamar o
# portal e o NÚMERO depois; quem volta e encontra intenção sem número tenta no máximo mais UMA vez,
# marcando a execução como possivelmente duplicada. Falha do envio (o portal disse que não fez)
# apaga a intenção, para a conversa não travar por um login intermitente.
#
# O que se prova aqui é o ESTADO — "intenção sem número" — e o que a passada seguinte faz com ele.
# NÃO se finge matar o processo: sinal não é o que esta suíte sabe reproduzir, e um teste que
# levanta exceção provaria outra coisa (a exceção é justamente o caso em que a intenção é apagada).
#
# PROVA POR MUTAÇÃO (10/09/2026): subir `MAXIMO_DE_INTENCOES` para 60 reprova "na terceira
# intenção, para"; tirar a anotação antes do `start` reprova "anota a intenção antes".
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
  let(:runs) { Autonomia::Agents::ToolRun }
  let(:intencoes) { Autonomia::Agents::ToolRun::INTENCOES }
  let(:duplicada) { Autonomia::Agents::ToolRun::POSSIVELMENTE_DUPLICADA }
  let(:submetido) { described_class::SUBMITTED_KEY }

  around { |example| with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { example.run } }

  def bot_contents
    conversation.messages.reload.where(sender_type: 'AgentBot').order(:id).map(&:content)
  end

  # Execução promovida, como o Responder deixa no fim do turno. `handle` é o estado em que a
  # passada começa: vazio (primeira vez) ou com intenção sem número (o worker morreu no meio).
  def execucao(handle: {})
    run = runs.open!(agent: agent, slug: 'consultar_cotacao', arguments: { 'placa' => 'ABC1D23' },
                     scope: { conversation_id: conversation.id, agent_inbox_id: agent_inbox.id })
    run.promote!(expected_chunks: 0, notify_customer: false, expires_at: 3.minutes.from_now)
    run.record_handle!(handle) if handle.present?
    run
  end

  # A ferramenta que, ao submeter, OLHA a linha: é assim que se prova que a intenção foi anotada
  # ANTES do portal ser chamado, e não depois.
  def ferramenta_que_le_a_linha(run_id, visto)
    linha = Autonomia::Agents::ToolRun
    build_async_tool(handle: { 'id' => 'cot-1' }, poll: Autonomia::Agents::Tools::Progress.running).tap do |tool|
      tool.define_method(:start) do
        visto << linha.find(run_id).handle
        { 'id' => 'cot-1' }
      end
    end
  end

  describe 'a ordem' do
    it 'anota a intencao ANTES de submeter e o numero DEPOIS' do
      # Arrange
      run = execucao
      visto = []
      register_async_tool(ferramenta_que_le_a_linha(run.id, visto))

      # Act
      described_class.new.perform(run.id, 0)

      # Assert — no momento do `start`, a linha já dizia "intenção 1" e ainda não dizia "submetido"
      expect(visto).to eq([{ intencoes => 1 }])
      expect(run.reload.handle).to include(submetido => true, 'id' => 'cot-1', intencoes => 1)
      expect(run.handle).not_to have_key(duplicada)
      expect(run.attempts).to eq(1)
    end
  end

  describe 'intencao sem numero (o worker morreu entre o envio e o registro)' do
    it 'tenta no maximo mais UMA vez, e marca como possivelmente duplicada' do
      # Arrange — a passada anterior anotou a intenção e morreu antes do número
      run = execucao(handle: { intencoes => 1 })
      tool = register_async_tool(build_async_tool(handle: { 'id' => 'cot-2' }))
      allow(tool).to receive(:new).and_call_original

      # Act
      described_class.new.perform(run.id, 0)

      # Assert
      expect(run.reload.handle).to include(submetido => true, 'id' => 'cot-2', intencoes => 2, duplicada => true)
      expect(runs.possivelmente_duplicadas).to eq([run])
      expect(described_class).to have_been_enqueued.with(run.id, 1)
    end

    it 'na terceira intencao, PARA: nunca sessenta' do
      # Arrange — já houve a repetição permitida, e o número de novo não chegou
      run = execucao(handle: { intencoes => 2, duplicada => true })
      tool = register_async_tool(build_async_tool(handle: { 'id' => 'cot-3' }))
      instance = instance_double(tool, start: { 'id' => 'cot-3' })
      allow(tool).to receive(:new).and_return(instance)

      # Act
      described_class.new.perform(run.id, 0)

      # Assert — o portal NÃO é chamado; o cliente é avisado; a marca fica para o corretor achar
      expect(instance).not_to have_received(:start)
      expect(run.reload).to have_attributes(status: 'failed', failure_code: 'envio_incerto')
      expect(run.handle).to include(duplicada => true)
      expect(bot_contents).to eq(['não consegui concluir a consulta'])
      expect(described_class).not_to have_been_enqueued
    end
  end

  describe 'falha do envio' do
    it 'apaga a intencao: o portal disse que nao fez, e a conversa nao trava' do
      # Arrange — login intermitente: o `start` levanta
      run = execucao
      register_async_tool(build_async_tool(start_error: 'AGGER login: no token in response, twice'))

      # Act
      described_class.new.perform(run.id, 0)

      # Assert — sem intenção anotada, sem marca de duplicata, e a execução segue viva
      expect(run.reload.handle).to eq({})
      expect(run.status).to eq('running')
      expect(described_class).to have_been_enqueued.with(run.id, 1)
    end

    it 'a passada seguinte submete como primeira intencao, sem marca de duplicata' do
      # Arrange — a falha anterior apagou a intenção
      run = execucao
      register_async_tool(build_async_tool(handle: { 'id' => 'cot-4' }))

      # Act
      described_class.new.perform(run.id, 1)

      # Assert
      expect(run.reload.handle).to include(submetido => true, intencoes => 1)
      expect(run.handle).not_to have_key(duplicada)
    end
  end

  describe 'as marcas sobrevivem' do
    it 'a consulta seguinte preserva intencoes e a marca de duplicata' do
      # Arrange — submetida como repetição, agora em consulta
      run = execucao(handle: { submetido => true, 'id' => 'cot-2', intencoes => 2, duplicada => true })
      register_async_tool(build_async_tool(poll: Autonomia::Agents::Tools::Progress.running(handle: { 'id' => 'cot-2', 'etapa' => 2 })))

      # Act
      described_class.new.perform(run.id, 1)

      # Assert — a ferramenta devolveu um handle novo SEM as nossas marcas, e elas voltaram
      expect(run.reload.handle).to include(submetido => true, 'etapa' => 2, intencoes => 2, duplicada => true)
    end

    it 'a ferramenta nunca ve as marcas' do
      run = execucao(handle: { submetido => true, 'id' => 'cot-2', intencoes => 2, duplicada => true })
      visto = []
      tool = build_async_tool(poll: Autonomia::Agents::Tools::Progress.running)
      tool.define_method(:poll) do |handle:, **|
        visto << handle
        Autonomia::Agents::Tools::Progress.running
      end
      register_async_tool(tool)

      described_class.new.perform(run.id, 1)

      expect(visto).to eq([{ 'id' => 'cot-2' }])
    end
  end

  describe 'o varredor' do
    it 'marca como possivelmente duplicada a execucao abandonada com intencao sem numero' do
      # Arrange — morreu com a intenção anotada, e ninguém voltou
      run = execucao(handle: { intencoes => 1 })
      run.update!(expires_at: 10.minutes.ago)
      register_async_tool(build_async_tool)

      # Act
      Autonomia::Agents::Tools::ReapStaleRunsJob.new.perform

      # Assert
      expect(run.reload).to have_attributes(status: 'failed', failure_code: 'execucao_abandonada')
      expect(runs.possivelmente_duplicadas).to eq([run])
    end

    it 'nao marca a abandonada que nem chegou a anotar intencao' do
      run = execucao
      run.update!(expires_at: 10.minutes.ago)
      register_async_tool(build_async_tool)

      Autonomia::Agents::Tools::ReapStaleRunsJob.new.perform

      expect(runs.possivelmente_duplicadas).to be_empty
    end
  end
end
