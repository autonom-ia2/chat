require 'rails_helper'

# UM EXEMPLO PARA CADA SAÍDA DE RECUSA (entrega 6, termo 3). A lista de motivos é o catálogo
# `Tools::Recusa::MOTIVOS`, e os exemplos são GERADOS a partir dela: motivo novo no catálogo sem
# gatilho aqui reprova a suíte — não dá para catalogar sem provar que dispara e registra.
#
# Cada gatilho percorre o caminho REAL — `Bound#execute`, o Runner do especialista, o
# `AsyncRunJob` —, nunca chama o registrador direto. É a diferença entre provar que a recusa
# registra e provar que o registrador funciona (isso é `recusa_spec`).
#
# PROVA POR MUTAÇÃO, feita em 10/09/2026: comentar a linha `Rails.logger.info` em
# `Recusa.registrar` derruba TODOS os exemplos deste arquivo.
RSpec.describe Autonomia::Agents::Tools::Recusa do
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
  let(:delivery) do
    Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: agent_inbox,
                                           origin_message_id: 77)
  end
  let(:tool) { build_async_tool(start_error: 'start nao roda no turno', poll_error: 'poll nao roda no turno') }
  let(:bound) { Autonomia::Agents::Tools::Bound.new(agent: agent, native: tool) }
  let(:call) { { 'name' => tool.slug, 'arguments' => '{"cpf":"000"}', 'call_id' => 'c1' } }
  let(:recusa) { described_class }
  let(:conferencia) { Autonomia::Agents::Tools::Native::Conferencia }
  let(:linhas) { [] }

  around { |example| with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { example.run } }

  before do
    allow(Rails.logger).to receive(:info).and_call_original
    allow(Rails.logger).to receive(:info).with(a_string_starting_with(recusa::PREFIXO)) { |texto| linhas << texto }
  end

  # O que cada exemplo afirma: a linha saiu UMA vez, com o motivo, e com a conversa e o agente
  # certos. `conversa` é `-` só quando a ausência dela é o próprio motivo.
  def padrao(motivo, conversa: conversation.id, onde: 'turno', faltando: '-', detalhe: '-')
    /\A#{Regexp.escape(recusa::PREFIXO)} slug=\S+ conversa=#{conversa} agente=#{agent.id} conta=#{account.id} \
onde=#{onde} motivo=#{motivo} faltando=#{Regexp.escape(faltando)} detalhe=#{Regexp.escape(detalhe)} descricao="[^"]+"\z/
  end

  # O especialista chama uma ferramenta que não tem (foi assim que a Lia ficou muda em 08/09/2026).
  def rodar_especialista_pedindo(nome)
    specialist = Autonomia::Agents::Specialist.create!(agent: agent, name: 'Auto', slug: 'auto',
                                                       description: 'cotação de automóvel',
                                                       instruction: 'Você cota automóvel.')
    resolver = instance_double(Crm::Ai::CredentialResolver, resolve: 'ai-credential')
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(resolver)
    client = instance_double(Crm::Ai::ResponsesClient)
    allow(client).to receive(:create_with_tool_executor) do |**_kwargs, &executor|
      executor.call([{ 'name' => nome, 'call_id' => 'c1', 'arguments' => '{}' }])
      { text: { resposta: 'ok', dados_faltando: [] }.to_json }
    end
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(client)
    Autonomia::Agents::Specialists::Runner.new(specialist: specialist, request: 'cotar', delivery: delivery).call
  end

  def bound_sincrono_que(&)
    native = Class.new(Autonomia::Agents::Tools::Native::Base) do
      def self.slug = 'ferramenta_de_teste'
      def self.description = 'teste'
      define_method(:call, &)
    end
    Autonomia::Agents::Tools::Bound.new(agent: agent, native: native)
  end

  def bound_http_que_falha_com(mensagem)
    record = Autonomia::Agents::Tool.create!(account: account, agent: agent, name: 'Estoque', slug: 'consultar_estoque',
                                             endpoint_url: 'https://exemplo.test/estoque', param_schema: [])
    allow(Autonomia::Agents::Tools::HttpExecutor).to receive(:new)
      .and_raise(Autonomia::Agents::Tools::HttpExecutor::Error, mensagem)
    Autonomia::Agents::Tools::Bound.new(agent: agent, record: record)
  end

  def bound_com_conferencia(resposta)
    Autonomia::Agents::Tools::Bound.new(agent: agent, native: build_async_tool(precheck: resposta))
  end

  # Gatilho por motivo, rodado com `instance_exec` no exemplo. Cada um DISPARA o caminho real e
  # devolve o que a linha registrada tem de diferente do padrão (conversa `-`, `faltando`, `detalhe`);
  # a expectativa fica no exemplo, uma só, para todos.
  def gatilhos # rubocop:disable Metrics/MethodLength, Metrics/AbcSize -- a tabela é o ponto: um gatilho por motivo
    {
      'invalid_tool_arguments' => lambda {
        bound.execute(call.merge('arguments' => 'nao-e-json'), delivery: delivery)
        {}
      },
      'tool_not_available' => lambda {
        rodar_especialista_pedindo('cotar_seguro')
        {}
      },
      'async_indisponivel_nesta_superficie' => lambda {
        bound.execute(call)
        { conversa: '-' }
      },
      'async_desligado' => lambda {
        with_modified_env(AI_AGENT_ASYNC_TOOLS: 'false') { bound.execute(call, delivery: delivery) }
        {}
      },
      'execucao_ja_aberta_neste_turno' => lambda {
        bound.execute(call, delivery: delivery)
        delivery.runs.first.promote!(expected_chunks: 0, notify_customer: false, expires_at: 3.minutes.from_now)
        retry_turn = Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: agent_inbox,
                                                            origin_message_id: 77)
        bound.execute(call, delivery: retry_turn)
        {}
      },
      'execucao_ja_em_andamento' => lambda {
        allow(Autonomia::Agents::ToolRun).to receive(:open!).and_return(nil)
        bound.execute(call, delivery: delivery)
        {}
      },
      # A ferramenta que só tem a frase: registra sem saber o que faltou.
      'conferencia_recusou' => lambda {
        bound_com_conferencia('Ainda preciso do CPF.').execute(call, delivery: delivery)
        {}
      },
      'faltam_dados' => lambda {
        resposta = conferencia.new(texto: 'Ainda preciso do CPF e do CEP.', motivo: 'faltam_dados',
                                   faltando: %w[insured.document address.zipCode])
        bound_com_conferencia(resposta).execute(call, delivery: delivery)
        { faltando: 'insured.document,address.zipCode' }
      },
      'json_invalido' => lambda {
        resposta = conferencia.new(texto: 'O campo dados não era JSON.', motivo: 'json_invalido', faltando: ['dados'])
        bound_com_conferencia(resposta).execute(call, delivery: delivery)
        { faltando: 'dados' }
      },
      'tool_execution_error' => lambda {
        bound_sincrono_que { raise 'X-Amz-Signature=abc' }.execute({ 'arguments' => '{}' }, delivery: delivery)
        {}
      },
      'tool_http_error' => lambda {
        bound_http_que_falha_com('tool_http_error: 503 Service Unavailable')
          .execute({ 'arguments' => '{}' }, delivery: delivery)
        { detalhe: '503' }
      }
    }
  end

  Autonomia::Agents::Tools::Recusa::MOTIVOS.each_key do |motivo|
    it "registra `#{motivo}` com conversa, agente e motivo" do
      gatilho = gatilhos.fetch(motivo) do
        raise "`#{motivo}` entrou em MOTIVOS sem gatilho aqui: catalogar sem provar que dispara não vale"
      end

      diferente = instance_exec(&gatilho)

      expect(linhas.size).to eq(1), "esperava 1 linha de recusa, saiu #{linhas.size}: #{linhas.inspect}"
      expect(linhas.first).to match(padrao(motivo, **diferente))
    end
  end

  it 'nao tem gatilho para motivo que nao esta no catalogo' do
    expect(gatilhos.keys - Autonomia::Agents::Tools::Recusa::MOTIVOS.keys).to be_empty
  end

  # A SEGUNDA PORTA: a conferência do turno passou (ou caiu) e a validação do `start` recusou.
  # A ferramenta não conhece a conversa; quem registra é o job, com `onde=envio`.
  describe 'no envio (AsyncRunJob)' do
    def run_promovida(ferramenta)
      run = Autonomia::Agents::ToolRun.open!(agent: agent, slug: ferramenta.slug, arguments: { 'placa' => 'ABC1D23' },
                                             scope: { conversation_id: conversation.id, agent_inbox_id: agent_inbox.id })
      run.promote!(expected_chunks: 0, notify_customer: false, expires_at: 3.minutes.from_now)
      run
    end

    it 'registra a recusa do start com conversa, agente e o que faltou' do
      # Arrange — o `start` devolve o handle de recusa que o `poll` reconhece
      recusada = register_async_tool(build_async_tool(handle: { 'pedido' => 'Preciso do CPF do titular.',
                                                                'motivo' => 'faltam_dados',
                                                                'faltando' => ['insured.document'] }))
      run = run_promovida(recusada)

      # Act
      Autonomia::Agents::Tools::AsyncRunJob.new.perform(run.id, 0)

      # Assert — registrou, e a execução seguiu o caminho normal (o pedido chega ao cliente pelo poll)
      expect(linhas.size).to eq(1)
      expect(linhas.first).to match(padrao('faltam_dados', onde: 'envio', faltando: 'insured.document'))
      expect(run.reload.handle).to include('pedido' => 'Preciso do CPF do titular.')
    end

    it 'nao registra quando o start submeteu de verdade' do
      run = run_promovida(register_async_tool(build_async_tool(handle: { 'quote_id' => 'cot-1' })))

      Autonomia::Agents::Tools::AsyncRunJob.new.perform(run.id, 0)

      expect(linhas).to be_empty
    end
  end
end
