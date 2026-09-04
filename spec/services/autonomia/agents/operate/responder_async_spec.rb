require 'rails_helper'

# FERRAMENTA ASSÍNCRONA dentro do turno de atendimento (#313).
#
# O critério da issue é "uma tool que demora 60s responde na conversa sem travar worker e sem
# duplicar mensagem". Aqui provamos a metade que mora no Responder: o turno ACEITA a ferramenta,
# entrega (ou cala) e só então PROMOVE a execução e enfileira o job — nada é executado de forma
# síncrona, e a linha carrega quem avisa o cliente (`notify_customer`) e quantos pedaços a entrega
# humanizada vai postar (`expected_chunks`).
#
# O Answerer NÃO é dublado: o ponto do teste é o repasse do `Tools::Delivery` até o executor de
# ferramentas. Dublados são só a credencial e o cliente de IA (mesmo padrão de
# `answerer_native_tools_spec.rb`), para que a chamada de ferramenta possa ser disparada.
RSpec.describe Autonomia::Agents::Operate::Responder do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:agent_bot) { create(:agent_bot, account: account) }

  let(:agent) do
    Autonomia::Agents::Agent.create!(
      account: account, name: 'Bot', agent_type: 'custom', status: :active, enabled: true,
      instruction: 'Atenda o cliente.', config: { 'with_knowledge' => false }
    )
  end

  let(:agent_inbox) do
    Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: agent_bot)
  end

  let(:tool) { build_async_tool(slug: 'consultar_cotacao') }
  let(:function_call) { { 'name' => 'consultar_cotacao', 'call_id' => 'c1', 'arguments' => '{"placa":"ABC1D23"}' } }

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true' do
      example.run
    end
  end

  before do
    register_async_tool(tool)
    agent.update!(config: agent.config.merge('native_tool_slugs' => [tool.slug]))
    conversation.update!(assignee_agent_bot_id: agent_bot.id)
    create(:message, account: account, conversation: conversation, message_type: :incoming, content: 'quanto fica o seguro?')
  end

  # Resposta do modelo no formato do schema do Answerer.
  def model_reply(text)
    { reply: text, confidence: 0.9, should_handoff: false, handoff_reason: nil,
      used_snippet_ids: [], answered_from_knowledge: false }.to_json
  end

  # Sobe o mínimo para o executor de ferramentas REAL rodar: credencial resolvida e um cliente que
  # chama o executor com a chamada de ferramenta e devolve `raw_text` como saída do modelo.
  def stub_ai_turn(raw_text)
    resolver = instance_double(Crm::Ai::CredentialResolver, resolve: 'ai-credential')
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(resolver)
    client = instance_double(Crm::Ai::ResponsesClient)
    allow(client).to receive(:create_with_tool_executor) do |**_kwargs, &executor|
      executor&.call([function_call])
      { text: raw_text }
    end
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(client)
  end

  def perform
    described_class.new(conversation: conversation, agent_inbox: agent_inbox).perform
  end

  describe 'classic delivery' do
    around do |example|
      with_modified_env AI_HUMANIZE_DELIVERY: 'false', AI_AGENT_MEDIA: 'false' do
        example.run
      end
    end

    it 'promotes the accepted run and enqueues the async job when the turn answers the customer' do
      # Arrange — o modelo chama a ferramenta E avisa o cliente na mesma resposta
      stub_ai_turn(model_reply('Já estou consultando a cotação, volto aqui com o resultado.'))

      # Act
      result = perform

      # Assert — nada rodou de forma síncrona: a execução saiu de pending para running e virou job
      run = Autonomia::Agents::ToolRun.last
      expect(result.status).to eq(:replied)
      expect(run).to have_attributes(slug: 'consultar_cotacao', status: 'running', notify_customer: false)
      expect(run.arguments).to eq('placa' => 'ABC1D23')
      expect(run.expires_at).to be_within(10.seconds).of(Autonomia::Agents::Tools::AsyncConfig::DEFAULT_DEADLINE_SECONDS.seconds.from_now)
      expect(Autonomia::Agents::Tools::AsyncRunJob).to have_been_enqueued.with(run.id, 0)
      # Uma mensagem só: quem avisa aqui é o modelo, o job não repete o aviso.
      expect(conversation.messages.outgoing.count).to eq(1)
    end

    it 'still dispatches, with the job owning the warning, when the instruction emits the silence signal' do
      # Arrange — a instrução manda calar, mas a consulta já foi aceita dentro do turno
      stub_ai_turn(model_reply(described_class::SILENCE_TOKEN))

      # Act
      result = perform

      # Assert
      run = Autonomia::Agents::ToolRun.last
      expect(result.status).to eq(:silenced)
      expect(conversation.messages.outgoing.count).to eq(0)
      expect(run).to have_attributes(status: 'running', notify_customer: true)
      expect(Autonomia::Agents::Tools::AsyncRunJob).to have_been_enqueued.with(run.id, 0)
    end

    it 'still dispatches, with the job owning the warning, when the model reply is unusable' do
      # Arrange — falha de IA: a saída não é JSON, o Answerer devolve reply nil
      stub_ai_turn('isto não é json')

      # Act
      result = perform

      # Assert
      run = Autonomia::Agents::ToolRun.last
      expect(result.status).to eq(:silenced)
      expect(conversation.messages.outgoing.count).to eq(0)
      expect(run).to have_attributes(status: 'running', notify_customer: true)
      expect(Autonomia::Agents::Tools::AsyncRunJob).to have_been_enqueued.with(run.id, 0)
    end

    it 'discards the accepted run, never calling the portal, when the turn dies before delivering' do
      # Arrange — o post falha depois de a ferramenta já ter sido aceita
      stub_ai_turn(model_reply('Já estou consultando.'))
      allow(Messages::MessageBuilder).to receive(:new).and_raise(StandardError, 'boom')

      # Act
      result = perform

      # Assert
      expect(result.status).to eq(:silenced)
      expect(Autonomia::Agents::ToolRun.last.status).to eq('discarded')
      expect(Autonomia::Agents::Tools::AsyncRunJob).not_to have_been_enqueued
    end

    it 'hands the answerer a delivery bound to this conversation and agent inbox' do
      # Arrange
      captured = nil
      allow(Autonomia::Agents::Answerer).to receive(:new).and_wrap_original do |original, **kwargs|
        captured = kwargs[:delivery]
        original.call(**kwargs)
      end
      stub_ai_turn(model_reply('Já estou consultando.'))

      # Act
      perform

      # Assert — é por este objeto que a ferramenta assíncrona sabe em que conversa publicar
      expect(captured).to be_a(Autonomia::Agents::Tools::Delivery)
      expect(captured.conversation).to eq(conversation)
      expect(captured.agent_inbox).to eq(agent_inbox)
      expect(captured.runs.map(&:slug)).to eq(['consultar_cotacao'])
    end
  end

  describe 'humanized delivery' do
    # Dois parágrafos, cada um acima do mínimo de caracteres: o quebrador produz mais de um pedaço.
    let(:reply) do
      "Perfeito! Já estou consultando a cotação do seu carro agora mesmo, com as seguradoras que atendem a sua região.\n\n" \
        'Assim que elas responderem eu trago os valores aqui nesta mesma conversa. Pode levar alguns instantes, tudo bem?'
    end

    around do |example|
      with_modified_env AI_HUMANIZE_DELIVERY: 'true', AI_AGENT_MEDIA: 'false' do
        example.run
      end
    end

    it 'records how many chunks the delivery chain will post so the publisher waits for them' do
      # Arrange
      expected = Autonomia::Agents::Operate::ReplyChunker.call(reply).length
      stub_ai_turn(model_reply(reply))

      # Act
      result = perform

      # Assert
      run = Autonomia::Agents::ToolRun.last
      expect(expected).to be > 1
      expect(result.status).to eq(:replied)
      expect(run).to have_attributes(status: 'running', expected_chunks: expected, notify_customer: false)
      expect(Autonomia::Agents::Operate::ChunkedDeliveryJob).to have_been_enqueued
      expect(Autonomia::Agents::Tools::AsyncRunJob).to have_been_enqueued.with(run.id, 0)
    end
  end
end
