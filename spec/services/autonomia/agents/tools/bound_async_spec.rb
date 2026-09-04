require 'rails_helper'

# O caminho ASSÍNCRONO do `Bound` (#313): a ferramenta que demora não pode rodar dentro do turno.
# Aqui se prova o contrato de ACEITE — o turno responde na hora, a execução fica registrada em
# `pending` para o Responder promover depois, e nada do portal é chamado agora.
RSpec.describe Autonomia::Agents::Tools::Bound do
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
  let(:delivery) { Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: agent_inbox) }
  # A ferramenta LEVANTA em `start` e em `poll`: se o turno executasse qualquer uma das duas, a saída
  # seria `tool_execution_error` em vez do aceite. É a prova de que o Bound só registra.
  let(:tool) do
    build_async_tool(start_error: 'start nao pode rodar dentro do turno',
                     poll_error: 'poll nao pode rodar dentro do turno')
  end
  let(:bound) { described_class.new(agent: agent, native: tool) }
  let(:call) { { 'name' => tool.slug, 'arguments' => '{"cpf":"000"}', 'call_id' => 'c1' } }
  let(:runs) { Autonomia::Agents::ToolRun }

  around { |example| with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { example.run } }

  # Retry do turno x pedido novo (#313). O settle do ReplyJob pode reexecutar e refazer a chamada ao
  # modelo; sem a chave da mensagem de origem, a segunda passada abriria OUTRA cotação no portal.
  describe '#execute across turns' do
    it 'refuses a second run for the same origin message once the first one is really running' do
      # Arrange — a execução do turno original foi DESPACHADA (é a que está falando com o portal)
      turn = Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: agent_inbox,
                                                    origin_message_id: 77)
      bound.execute(call, delivery: turn)
      turn.runs.first.promote!(expected_chunks: 0, notify_customer: false, expires_at: 3.minutes.from_now)

      # Act — o settle do ReplyJob reexecutou e o modelo pediu a mesma ferramenta de novo
      retry_turn = Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: agent_inbox,
                                                          origin_message_id: 77)
      output = bound.execute(call, delivery: retry_turn)

      # Assert
      expect(JSON.parse(output)).to eq('error' => 'execucao_ja_aberta_neste_turno')
      expect(runs.where(conversation_id: conversation.id).count).to eq(1)
      expect(retry_turn.runs).to be_empty
    end

    # A `pending` órfã é o rastro de um turno cujo worker morreu antes de despachar (um deploy basta).
    # Se ela bloqueasse o retry, a cotação nunca aconteceria — o cliente esperaria para sempre.
    it 'lets the turn retry through when the first run was never dispatched' do
      # Arrange — aceita e NÃO promove: exatamente o que sobra de um worker morto no meio
      turn = Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: agent_inbox,
                                                    origin_message_id: 77)
      bound.execute(call, delivery: turn)

      # Act
      retry_turn = Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: agent_inbox,
                                                          origin_message_id: 77)
      output = bound.execute(call, delivery: retry_turn)

      # Assert — a órfã é supersedida e a nova assume; continua UMA execução viva
      expect(output).to eq(tool.accepted_message)
      expect(turn.runs.first.reload.status).to eq('superseded')
      expect(runs.where(conversation_id: conversation.id).active.count).to eq(1)
    end

    it 'supersedes the live run when a new customer message asks again' do
      # Arrange
      first = Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: agent_inbox,
                                                     origin_message_id: 77)
      bound.execute(call, delivery: first)

      # Act — mensagem NOVA do cliente ("na verdade e 2019")
      second = Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: agent_inbox,
                                                      origin_message_id: 78)
      output = bound.execute(call, delivery: second)

      # Assert
      expect(output).to eq(tool.accepted_message)
      expect(first.runs.first.reload.status).to eq('superseded')
      expect(runs.where(conversation_id: conversation.id).active.count).to eq(1)
    end
  end

  describe '#execute with a delivery' do
    it 'answers the model with the accepted message instead of the tool result' do
      # Arrange / Act
      output = bound.execute(call, delivery: delivery)

      # Assert
      expect(output).to eq('aceito: consulta iniciada')
      expect(output).to eq(tool.accepted_message)
    end

    it 'never instantiates the tool, so a 60s call cannot hold the turn' do
      # Arrange
      allow(tool).to receive(:new).and_call_original

      # Act
      output = bound.execute(call, delivery: delivery)

      # Assert
      expect(tool).not_to have_received(:new)
      expect(output).to eq(tool.accepted_message)
      expect(runs.last.handle).to eq({})
      expect(runs.last.attempts).to be_zero
    end

    it 'records exactly one pending run carrying the arguments the model built' do
      # Arrange / Act
      bound.execute(call, delivery: delivery)

      # Assert
      run = runs.last
      expect(runs.count).to eq(1)
      expect(run.status).to eq('pending')
      expect(run.slug).to eq(tool.slug)
      expect(run.arguments).to eq({ 'cpf' => '000' })
      expect(run.conversation_id).to eq(conversation.id)
      expect(run.agent_inbox_id).to eq(agent_inbox.id)
      expect(run.account_id).to eq(account.id)
    end

    it 'hands the accepted run back to the turn through the delivery' do
      # Arrange / Act
      bound.execute(call, delivery: delivery)

      # Assert
      expect(delivery).to be_any_runs
      expect(delivery.runs.map(&:id)).to eq([runs.last.id])
    end

    # "sem duplicar mensagem": duas aceitações na mesma conversa não podem virar duas cotações vivas.
    it 'supersedes the live run instead of keeping two quotes in flight' do
      # Arrange
      bound.execute(call, delivery: delivery)
      first = runs.last

      # Act
      bound.execute(call.merge('arguments' => '{"cpf":"111"}'), delivery: delivery)

      # Assert
      expect(runs.count).to eq(2)
      expect(first.reload.status).to eq('superseded')
      expect(runs.active.count).to eq(1)
      expect(runs.active.last.arguments).to eq({ 'cpf' => '111' })
    end
  end

  describe '#execute refusals' do
    it 'refuses without a delivery, because there is no conversation to answer into' do
      # Arrange / Act
      output = bound.execute(call)

      # Assert
      expect(output).to eq({ error: 'async_indisponivel_nesta_superficie' }.to_json)
      expect(runs.count).to be_zero
    end

    it 'refuses a delivery that carries no conversation' do
      # Arrange
      surface = Autonomia::Agents::Tools::Delivery.new(conversation: nil, agent_inbox: agent_inbox)

      # Act
      output = bound.execute(call, delivery: surface)

      # Assert
      expect(output).to eq({ error: 'async_indisponivel_nesta_superficie' }.to_json)
      expect(runs.count).to be_zero
    end

    it 'refuses with a named error when the kill switch is off' do
      # Arrange / Act
      output = with_modified_env(AI_AGENT_ASYNC_TOOLS: 'false') { bound.execute(call, delivery: delivery) }

      # Assert
      expect(output).to eq({ error: 'async_desligado' }.to_json)
      expect(runs.count).to be_zero
    end

    it 'refuses above the per-conversation ceiling inside the window' do
      # Arrange — linhas antigas em estado TERMINAL, para não colidir com o índice único de ativas
      create_finished_runs(Autonomia::Agents::Tools::AsyncConfig::MAX_RUNS_PER_CONVERSATION)

      # Act
      output = bound.execute(call, delivery: delivery)

      # Assert
      expect(output).to eq({ error: 'limite_de_execucoes_atingido' }.to_json)
      expect(runs.active.count).to be_zero
    end

    it 'accepts again once the old runs fall outside the window' do
      # Arrange
      create_finished_runs(Autonomia::Agents::Tools::AsyncConfig::MAX_RUNS_PER_CONVERSATION,
                           created_at: (Autonomia::Agents::Tools::AsyncConfig::RUNS_WINDOW + 1.minute).ago)

      # Act
      output = bound.execute(call, delivery: delivery)

      # Assert
      expect(output).to eq(tool.accepted_message)
      expect(runs.active.count).to eq(1)
    end

    it 'reports invalid arguments before opening any run' do
      # Arrange / Act
      output = bound.execute(call.merge('arguments' => 'nao-e-json'), delivery: delivery)

      # Assert
      expect(output).to eq({ error: 'invalid_tool_arguments' }.to_json)
      expect(runs.count).to be_zero
    end
  end

  # REGRESSÃO: `delivery:` é opcional e não muda o caminho síncrono, que continua executando no turno.
  describe '#execute on the synchronous path' do
    let(:sync_native) do
      Class.new(Autonomia::Agents::Tools::Native::Base) do
        def self.slug = 'ferramenta_sincrona'
        def self.description = 'teste'
        def call = "conta #{account.id}"
      end
    end

    it 'still runs a synchronous native tool when a delivery comes along' do
      # Arrange
      sync_bound = described_class.new(agent: agent, native: sync_native)

      # Act
      output = sync_bound.execute({ 'name' => 'ferramenta_sincrona', 'arguments' => '{}' }, delivery: delivery)

      # Assert
      expect(output).to eq("conta #{account.id}")
      expect(runs.count).to be_zero
      expect(delivery).not_to be_any_runs
    end
  end

  def create_finished_runs(total, created_at: Time.current)
    total.times do
      runs.create!(account: account, agent: agent, conversation_id: conversation.id,
                   agent_inbox_id: agent_inbox.id, slug: tool.slug, status: 'done',
                   execution_key: SecureRandom.uuid, created_at: created_at)
    end
  end
end
