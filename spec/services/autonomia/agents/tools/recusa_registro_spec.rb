require 'rails_helper'

# UM EXEMPLO PARA CADA SAÍDA DE RECUSA (entrega 6, termo 3). As saídas vêm da VARREDURA
# (`VarreduraDeRecusas.saidas`: toda chamada ao registrador e todo `return 'codigo'` do Bound, com o
# método que a contém) e os exemplos são chaveados por SAÍDA — `bound.rb#accept_async#2` —, não por
# motivo. Saída nova sem gatilho aqui reprova; gatilho para saída que não existe mais reprova; motivo
# do catálogo que nenhum gatilho espera reprova.
#
# Cada gatilho percorre o caminho REAL: `Bound#execute`, o `Answerer`, o Runner do especialista, o
# `AsyncRunJob`, e a ferramenta de cotação DE VERDADE (com o conector `mock`, que valida como o
# adapter). Nunca chama o registrador direto — isso é `recusa_spec`.
#
# PROVA POR MUTAÇÃO (10/09/2026): `Rails.logger.debug` no lugar de `info` no registrador derruba
# todos os exemplos; apagar uma entrada da tabela reprova "saída sem gatilho".
RSpec.describe Autonomia::Agents::Tools::Recusa do
  let(:account) do
    create(:account, internal_attributes: { 'autonomia_agents_enabled' => true, 'autonomia_insurance_enabled' => true })
  end
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom', status: :active,
                                     enabled: true, instruction: 'Atenda o cliente.', config: { 'with_knowledge' => false })
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
  let(:cotacao) { Autonomia::Agents::Tools::Native::InsuranceQuote }
  let(:linhas) { [] }

  around do |example|
    with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true', INSURANCE_QUOTING_ENABLED: 'true') { example.run }
  end

  before do
    enable_test_encryption!
    allow(Rails.logger).to receive(:info).and_call_original
    allow(Rails.logger).to receive(:info).with(a_string_starting_with(described_class::PREFIXO)) { |texto| linhas << texto }
  end

  # O que cada exemplo afirma: a linha saiu UMA vez, com o motivo, e com a conversa e o agente
  # certos. `conversa` é `-` só quando a ausência dela é o próprio motivo (ou a ferramenta síncrona
  # não a conhece). `faltando` aceita Regexp para a ferramenta real, que devolve mais de um campo.
  def padrao(motivo:, **diferencas)
    e = { slug: 'consultar_cotacao', conversa: conversation.id, onde: 'turno', faltando: '-', detalhe: '-' }.merge(diferencas)
    campos = e[:faltando].is_a?(Regexp) ? e[:faltando].source : Regexp.escape(e[:faltando])
    frase = Regexp.escape(described_class::MOTIVOS.fetch(motivo))
    /\A#{Regexp.escape(described_class::PREFIXO)} slug=#{e[:slug]} conversa=#{e[:conversa]} agente=#{agent.id} conta=#{account.id} \
onde=#{e[:onde]} motivo=#{motivo} faltando=#{campos} detalhe=#{Regexp.escape(e[:detalhe])} descricao="#{frase}"\z/
  end

  def ready_connection
    record = Autonomia::Insurance::Connection.create!(account: account, username: 'c@x.com', password: 'segredo')
    record.update!(status: 'ready')
    record.store_session!({ 'multicalculoToken' => 'multi' }, expires_at: 3.hours.from_now)
    record
  end

  def bound_para(native)
    Autonomia::Agents::Tools::Bound.new(agent: agent, native: native)
  end

  def bound_com_conferencia(resposta)
    bound_para(build_async_tool(precheck: resposta))
  end

  def bound_sincrono_que(&)
    native = Class.new(Autonomia::Agents::Tools::Native::Base) do
      def self.slug = 'ferramenta_de_teste'
      def self.description = 'teste'
      define_method(:call, &)
    end
    bound_para(native)
  end

  def bound_http_que_falha_com(mensagem)
    record = Autonomia::Agents::Tool.create!(account: account, agent: agent, name: 'Estoque', slug: 'consultar_estoque',
                                             endpoint_url: 'https://exemplo.test/estoque', param_schema: [])
    allow(Autonomia::Agents::Tools::HttpExecutor).to receive(:new)
      .and_raise(Autonomia::Agents::Tools::HttpExecutor::Error, mensagem)
    Autonomia::Agents::Tools::Bound.new(agent: agent, record: record)
  end

  def criar_especialista
    Autonomia::Agents::Specialist.create!(agent: agent, name: 'Auto', slug: 'auto', description: 'cotação de automóvel',
                                          instruction: 'Você cota automóvel.')
  end

  # O modelo é um dublê que devolve a chamada de função pedida e depois uma resposta válida.
  def modelo_que_chama(function_call, resposta)
    resolver = instance_double(Crm::Ai::CredentialResolver, resolve: 'ai-credential')
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(resolver)
    client = instance_double(Crm::Ai::ResponsesClient)
    allow(client).to receive(:create_with_tool_executor) do |**_kwargs, &executor|
      executor&.call([function_call])
      { text: resposta.to_json }
    end
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(client)
  end

  # O PRINCIPAL (Answerer) recebe uma chamada de função do modelo e a roteia.
  def rodar_principal(function_call)
    modelo_que_chama(function_call, reply: 'ok', confidence: 0.9, should_handoff: false, handoff_reason: nil,
                                    used_snippet_ids: [], answered_from_knowledge: false)
    Autonomia::Agents::Answerer.new(agent: agent, query: 'quero cotar', trust_instruction: true, delivery: delivery).answer
  end

  # O ESPECIALISTA chama uma ferramenta que não tem (foi assim que a Lia ficou muda em 08/09/2026).
  def rodar_especialista_pedindo(nome)
    modelo_que_chama({ 'name' => nome, 'call_id' => 'c1', 'arguments' => '{}' }, resposta: 'ok', dados_faltando: [])
    Autonomia::Agents::Specialists::Runner.new(specialist: criar_especialista, request: 'cotar', delivery: delivery).call
  end

  # O ESPECIALISTA que não chega a trabalhar: sem pedido, sem credencial, modelo fora do formato,
  # exceção, ou resposta vazia.
  def rodar_especialista(request: 'cotar', credencial: 'ai-credential', texto: nil, erro: nil)
    resolver = instance_double(Crm::Ai::CredentialResolver, resolve: credencial)
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(resolver)
    client = instance_double(Crm::Ai::ResponsesClient)
    if erro
      allow(client).to receive(:create_with_tool_executor).and_raise(erro)
    else
      allow(client).to receive(:create_with_tool_executor).and_return({ text: texto })
    end
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(client)
    Autonomia::Agents::Specialists::Runner.new(specialist: criar_especialista, request: request, delivery: delivery).call
  end

  def run_promovida(ferramenta, arguments: { 'placa' => 'ABC1D23' })
    run = Autonomia::Agents::ToolRun.open!(agent: agent, slug: ferramenta.slug, arguments: arguments,
                                           scope: { conversation_id: conversation.id, agent_inbox_id: agent_inbox.id })
    run.promote!(expected_chunks: 0, notify_customer: false, expires_at: 3.minutes.from_now)
    run
  end

  def rodar_job(ferramenta, arguments: { 'placa' => 'ABC1D23' })
    Autonomia::Agents::Tools::AsyncRunJob.new.perform(run_promovida(register_async_tool(ferramenta), arguments: arguments).id, 0)
  end

  # Um gatilho por SAÍDA da varredura. `dispara` roda com `instance_exec` no exemplo; `espera` é o
  # que a linha registrada tem de diferente do padrão.
  def gatilhos # rubocop:disable Metrics/MethodLength, Metrics/AbcSize -- a tabela é o ponto: um gatilho por saída
    {
      'bound.rb#execute#1' => {
        espera: { motivo: 'invalid_tool_arguments' },
        dispara: -> { bound.execute(call.merge('arguments' => 'nao-e-json'), delivery: delivery) }
      },
      # As três razões de `async_refusal` saem por esta chamada; cada `return` tem o seu gatilho abaixo.
      'bound.rb#accept_async#1' => {
        espera: { motivo: 'async_indisponivel_nesta_superficie', conversa: '-' },
        dispara: -> { bound.execute(call) }
      },
      # O caminho real: a segunda inserção perde para o índice único e `open!` resgata `RecordNotUnique`.
      'bound.rb#accept_async#2' => {
        espera: { motivo: 'execucao_ja_em_andamento' },
        dispara: lambda {
          allow(Autonomia::Agents::ToolRun).to receive(:create!).and_raise(ActiveRecord::RecordNotUnique, 'idx_active')
          bound.execute(call, delivery: delivery)
        }
      },
      'bound.rb#accept_async#3' => {
        espera: { motivo: 'tool_execution_error' },
        dispara: lambda {
          allow(Autonomia::Agents::ToolRun).to receive(:open!).and_raise('X-Amz-Signature=abc')
          bound.execute(call, delivery: delivery)
        }
      },
      # "E aí, saiu?" (entrega 10): o mesmo pedido, noutra mensagem, com a consulta ainda rodando.
      'bound.rb#recusar_pela_repeticao#1' => {
        espera: { motivo: 'pedido_repetido', slug: 'cotar_seguro', onde: 'aceite' },
        dispara: lambda {
          ready_connection
          chamada = { 'name' => 'cotar_seguro', 'call_id' => 'c2',
                      'arguments' => '{"cpf":"04297912678","placa":"ABC1D23","cep":"30130000"}' }
          bound_para(cotacao).execute(chamada, delivery: delivery)
          delivery.runs.last.promote!(expected_chunks: 0, notify_customer: false, expires_at: 3.minutes.from_now)
          outra = Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: agent_inbox,
                                                         origin_message_id: 78)
          bound_para(cotacao).execute(chamada, delivery: outra)
        }
      },
      # A ferramenta que só tem a frase: registra sem saber o que faltou.
      'bound.rb#recusar_pela_conferencia#1' => {
        espera: { motivo: 'conferencia_recusou' },
        dispara: -> { bound_com_conferencia('Ainda preciso do CPF.').execute(call, delivery: delivery) }
      },
      'bound.rb#run_http#1' => {
        espera: { motivo: 'tool_http_error', slug: 'consultar_estoque', detalhe: '503' },
        dispara: lambda {
          bound_http_que_falha_com('tool_http_error: 503 Service Unavailable').execute({ 'arguments' => '{}' }, delivery: delivery)
        }
      },
      'bound.rb#run_native#1' => {
        espera: { motivo: 'tool_execution_error', slug: 'ferramenta_de_teste' },
        dispara: -> { bound_sincrono_que { raise 'X-Amz-Signature=abc' }.execute({ 'arguments' => '{}' }, delivery: delivery) }
      },
      'bound.rb#async_refusal#1' => {
        espera: { motivo: 'async_indisponivel_nesta_superficie', conversa: '-' },
        dispara: -> { bound.execute(call, delivery: Autonomia::Agents::Tools::Delivery.new(conversation: nil, agent_inbox: agent_inbox)) }
      },
      'bound.rb#async_refusal#2' => {
        espera: { motivo: 'async_desligado' },
        dispara: -> { with_modified_env(AI_AGENT_ASYNC_TOOLS: 'false') { bound.execute(call, delivery: delivery) } }
      },
      'bound.rb#async_refusal#3' => {
        espera: { motivo: 'execucao_ja_aberta_neste_turno' },
        dispara: lambda {
          bound.execute(call, delivery: delivery)
          delivery.runs.first.promote!(expected_chunks: 0, notify_customer: false, expires_at: 3.minutes.from_now)
          retry_turn = Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: agent_inbox,
                                                              origin_message_id: 77)
          bound.execute(call, delivery: retry_turn)
        }
      },
      'answerer.rb#dispatch_tool_call#1' => {
        # Nome que não existe em catálogo nenhum não vai ao registro: o modelo repete o que o cliente escreve.
        espera: { motivo: 'tool_not_available', slug: 'desconhecida' },
        dispara: -> { rodar_principal('name' => 'ferramenta_que_nao_existe', 'call_id' => 'c1', 'arguments' => '{}') }
      },
      'answerer.rb#run_specialist#1' => {
        espera: { motivo: 'invalid_tool_arguments', slug: 'consultar_auto' },
        dispara: -> { rodar_principal('name' => criar_especialista.function_name, 'call_id' => 'c1', 'arguments' => 'nao-e-json') }
      },
      'runner.rb#sem_ferramenta#1' => {
        espera: { motivo: 'tool_not_available', slug: 'cotar_seguro' },
        dispara: -> { rodar_especialista_pedindo('cotar_seguro') }
      },
      'runner.rb#call#1' => {
        espera: { motivo: 'especialista_sem_pedido', slug: 'consultar_auto' },
        dispara: -> { rodar_especialista(request: '   ') }
      },
      'runner.rb#call#2' => {
        espera: { motivo: 'especialista_sem_credencial', slug: 'consultar_auto' },
        dispara: -> { rodar_especialista(credencial: nil) }
      },
      'runner.rb#call#3' => {
        espera: { motivo: 'especialista_sem_resposta', slug: 'consultar_auto' },
        dispara: -> { rodar_especialista(texto: 'nao-e-json') }
      },
      'runner.rb#call#4' => {
        espera: { motivo: 'especialista_falhou', slug: 'consultar_auto' },
        dispara: -> { rodar_especialista(erro: RuntimeError.new('X-Amz-Signature=abc')) }
      },
      'runner.rb#format_result#1' => {
        espera: { motivo: 'especialista_nao_concluiu', slug: 'consultar_auto' },
        dispara: -> { rodar_especialista(texto: { resposta: '', dados_faltando: [] }.to_json) }
      },
      # A ferramenta de cotação DE VERDADE: no envio (o job registra) e no turno (o Bound registra).
      'insurance_quote.rb#start#1' => {
        espera: { motivo: 'json_invalido', slug: 'cotar_seguro', onde: 'envio', faltando: 'dados' },
        dispara: lambda {
          ready_connection
          rodar_job(cotacao, arguments: { 'produto' => 'bike', 'dados' => '{marca: Caloi' })
        }
      },
      'insurance_quote.rb#start#2' => {
        espera: { motivo: 'faltam_dados', slug: 'cotar_seguro', onde: 'envio', faltando: /[a-zA-Z.,]*insured\.document[a-zA-Z.,]*/ },
        dispara: lambda {
          ready_connection
          rodar_job(cotacao, arguments: { 'produto' => 'auto', 'placa' => 'ABC1D23' })
        }
      },
      'insurance_quote.rb#precheck#1' => {
        espera: { motivo: 'json_invalido', slug: 'cotar_seguro', faltando: 'dados' },
        dispara: lambda {
          ready_connection
          bound_para(cotacao).execute({ 'name' => 'cotar_seguro', 'arguments' => { produto: 'bike', dados: '{marca: Caloi' }.to_json },
                                      delivery: delivery)
        }
      },
      'insurance_quote.rb#precheck#2' => {
        espera: { motivo: 'faltam_dados', slug: 'cotar_seguro', faltando: /[a-zA-Z.,]*insured\.document[a-zA-Z.,]*/ },
        dispara: lambda {
          ready_connection
          bound_para(cotacao).execute({ 'name' => 'cotar_seguro', 'arguments' => { produto: 'auto', placa: 'ABC1D23' }.to_json },
                                      delivery: delivery)
        }
      },
      # Ramo que o adapter não tem: recusa na conferência (nenhuma execução aberta) e no envio.
      'insurance_quote.rb#precheck#3' => {
        espera: { motivo: 'ramo_desconhecido', slug: 'cotar_seguro', faltando: 'produto' },
        dispara: lambda {
          ready_connection
          bound_para(cotacao).execute({ 'name' => 'cotar_seguro', 'arguments' => { produto: 'drone', dados: '{}' }.to_json },
                                      delivery: delivery)
          expect(Autonomia::Agents::ToolRun.count).to be_zero
        }
      },
      'insurance_quote.rb#start#3' => {
        espera: { motivo: 'ramo_desconhecido', slug: 'cotar_seguro', onde: 'envio', faltando: 'produto' },
        dispara: lambda {
          ready_connection
          rodar_job(cotacao, arguments: { 'produto' => 'drone', 'dados' => '{}' })
        }
      },
      'async_run_job.rb#registrar_recusa#1' => {
        espera: { motivo: 'faltam_dados', onde: 'envio', faltando: 'insured.document' },
        dispara: lambda {
          rodar_job(build_async_tool(handle: { 'pedido' => 'Preciso do CPF do titular.', 'motivo' => 'faltam_dados',
                                               'faltando' => ['insured.document'] }))
        }
      },
      # As ferramentas SÍNCRONAS de verdade: a de ramos, em JSON; a de condições gerais, em prosa.
      'insurance_capabilities.rb#call#1' => {
        espera: { motivo: 'capabilities_unavailable', slug: 'consultar_produtos_cotacao' },
        dispara: lambda {
          allow(Autonomia::Insurance::Connection).to receive(:for_account).and_raise('X-Amz-Signature=abc')
          bound_para(Autonomia::Agents::Tools::Native::InsuranceCapabilities).execute({ 'arguments' => '{}' }, delivery: delivery)
        }
      },
      'insurance_general_conditions.rb#call#1' => {
        espera: { motivo: 'condicoes_sem_seguradora', slug: 'consultar_condicoes_gerais', faltando: 'seguradora' },
        dispara: lambda {
          bound_para(Autonomia::Agents::Tools::Native::InsuranceGeneralConditions).execute({ 'arguments' => '{}' }, delivery: delivery)
        }
      },
      'insurance_general_conditions.rb#call#2' => {
        espera: { motivo: 'condicoes_sem_pergunta', slug: 'consultar_condicoes_gerais', faltando: 'pergunta' },
        dispara: lambda {
          bound_para(Autonomia::Agents::Tools::Native::InsuranceGeneralConditions)
            .execute({ 'arguments' => { seguradora: 'Porto' }.to_json }, delivery: delivery)
        }
      }
    }
  end

  VarreduraDeRecusas.saidas.each do |saida|
    it "registra a saída #{saida.id} (#{saida.arquivo}:#{saida.linha})" do
      gatilho = gatilhos.fetch(saida.id) do
        raise "saída nova sem gatilho: #{saida}. Uma saída de recusa só entra com o exemplo que prova o registro."
      end

      instance_exec(&gatilho[:dispara])

      expect(linhas.size).to eq(1), "esperava 1 linha de recusa, saiu #{linhas.size}: #{linhas.inspect}"
      expect(linhas.first).to match(padrao(**gatilho[:espera]))
    end
  end

  it 'nao tem gatilho para saida que nao existe mais' do
    expect(gatilhos.keys - VarreduraDeRecusas.saidas.map(&:id)).to be_empty
  end

  it 'todo motivo do catalogo e esperado por algum gatilho' do
    esperados = gatilhos.values.map { |gatilho| gatilho[:espera][:motivo] }.uniq

    expect(described_class::MOTIVOS.keys - esperados).to be_empty
    expect(esperados - described_class::MOTIVOS.keys).to be_empty
  end

  it 'nao registra quando o start submeteu de verdade' do
    rodar_job(build_async_tool(handle: { 'quote_id' => 'cot-1' }))

    expect(linhas).to be_empty
  end

  # O registro é cortesia sobre um caminho que já deu errado: se ele falhar, o pedido ao cliente
  # continua seguindo (o handle é gravado e o `poll` entrega).
  it 'nao derruba a execucao quando o registro do envio falha' do
    allow(described_class).to receive(:registrar).and_raise(IOError, 'disco cheio')
    recusada = build_async_tool(handle: { 'pedido' => 'Preciso do CPF.', 'motivo' => 'faltam_dados', 'faltando' => ['x'] })

    run = run_promovida(register_async_tool(recusada))
    expect { Autonomia::Agents::Tools::AsyncRunJob.new.perform(run.id, 0) }.not_to raise_error

    expect(run.reload.handle).to include('pedido' => 'Preciso do CPF.')
  end
end
