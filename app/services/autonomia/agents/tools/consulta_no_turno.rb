# A CONSULTA HTTP EM SEGUNDO PLANO, DO LADO DO TURNO (#1430, desenho D aprovado pelo Rodrigo).
#
# Com a flag `agente_ferramenta_em_segundo_plano` e uma conversa, TODA chamada da ferramenta HTTP sai do turno: abre
# uma execução `running` e enfileira o `HttpAssincronaJob` na fila `agent_tools` na hora. O turno espera por ela até
# `ESPERA_DO_TURNO`, contados do PRIMEIRO disparo do turno (o prazo mora no `Delivery`), lendo só o estado da linha.
#   - Chegou na janela: o modelo lê o mesmo texto do síncrono (a resposta com o teto, ou a recusa HTTP).
#   - Não chegou: o modelo lê `EM_ANDAMENTO`, e o resultado chega por evento (`consulta_concluida`/`consulta_falhou`)
#     num turno novo.
# A decisão é pelo tempo REAL da resposta, não pelo configurado: o único limite é o `timeout_seconds` da ferramenta.
#
# QUEM ENTREGA é decidido por uma marca só na linha (`ToolRun::ConsultaHttp::ENTREGA`), por compare-and-set: o turno
# marca `entregue_no_turno` ou `desistiu_do_turno`, e a desistência só vale sem resultado gravado. O job só dispara o
# evento com a desistência. Na corrida, a entrega acontece uma vez.
#
# A MESMA CHAMADA (a mesma Idempotency-Key) com a execução rodando REUSA a execução: na mesma passada (o pré-disparo da
# rodada e a execução da chamada) e no turno refeito. Nunca uma segunda chamada HTTP.
#
# Sem conversa (Testar, playground, Copiloto) ou sem a flag, nada daqui roda: a ferramenta é síncrona, como no #2426.
class Autonomia::Agents::Tools::ConsultaNoTurno
  ToolRun = ::Autonomia::Agents::ToolRun
  Chave = ::Autonomia::Agents::Tools::ChaveDeIdempotencia

  FLAG = 'agente_ferramenta_em_segundo_plano'.freeze
  ESPERA_DO_TURNO = 8
  # De quanto em quanto tempo o turno lê o estado da linha (só a coluna).
  INTERVALO = 0.25
  EM_ANDAMENTO = 'Consulta em andamento. Avise o cliente que você está consultando e que responde assim que tiver o ' \
                 'resultado.'.freeze
  FIM = %w[done failed].freeze

  # Com conversa (o `Delivery` do turno, também o do principal quando quem chama é o ajudante) e a flag da conta.
  def self.aplica?(tool, turno)
    turno.respond_to?(:conversation) && turno.conversation.present? && ligada?(tool.account)
  end

  # O bit da flag entra no config/features.yml pela Orquestração (ext_2, posição 23). Enquanto ele não está lá, o
  # `feature_<flag>?` não existe e a conta segue o caminho síncrono do #2426, em vez de levantar em toda chamada HTTP.
  def self.ligada?(account)
    account.respond_to?("feature_#{FLAG}?") && account.feature_enabled?(FLAG)
  end

  # Os dois relógios da espera, em métodos de classe para o spec dublar: o monotônico e a pausa entre leituras.
  def self.agora
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def self.pausar(segundos)
    sleep(segundos)
  end

  # `agente`: quem fala nesta conversa (o principal). A execução é dele: é ele quem fala do resultado no evento.
  # Levanta `HttpExecutor::ValorRecusado` quando um valor não converte: o `Bound` recusa como no síncrono.
  def initialize(tool:, agente:, turno:, args:)
    @tool = tool
    @agente = agente
    @turno = turno
    @params = ::Autonomia::Agents::Tools::ParamsTipados.converter(args.to_h.deep_stringify_keys, tool.param_schema)
    @chave = Chave.para(tool: tool, turno: turno, params: @params)
  end

  # -> a execução desta chamada: a que o turno já disparou, a que roda com a mesma chave (o turno refeito), ou uma nova.
  def disparar
    @turno.prazo_das_consultas(self.class.agora, ESPERA_DO_TURNO)
    @turno.consultas[@chave] ||= reusada || abrir
  end

  # -> o texto que o modelo lê.
  def resultado
    run = disparar.reload
    return EM_ANDAMENTO if run.entrega == ToolRun::DESISTIU_DO_TURNO

    inicio = self.class.agora
    status = aguardar(run)
    return entregar(run) if FIM.include?(status)
    return desistir(run, inicio) if status == 'running'

    status == 'superseded' ? EM_ANDAMENTO : ::Autonomia::Agents::Tools::Recusa.saida('tool_execution_error')
  end

  private

  # Lê SÓ o estado, de `INTERVALO` em `INTERVALO`, até o prazo do turno; entre as leituras, a conexão do banco volta
  # ao pool. -> o último estado lido.
  def aguardar(run)
    loop do
      status = ToolRun.where(id: run.id).pick(:status)
      restante = @turno.prazo_das_consultas(self.class.agora, ESPERA_DO_TURNO) - self.class.agora
      return status if status != 'running' || restante <= 0

      ::Autonomia::Agents::Tools::ConexaoDoBanco.soltar
      self.class.pausar([INTERVALO, restante].min)
    end
  end

  # O resultado chegou. Quem marcou a entrega primeiro decide: este turno, ou um que já desistiu (o evento fala).
  # A resposta 2xx avança a ocorrência do turno: a próxima chamada idêntica é outro pedido (`Delivery#ocorrencia`).
  def entregar(run)
    run.reload
    if run.marcar_entregue!
      @turno.concluir(Chave.pedido(@tool, @turno, @params)) if run.resultado_ok?
    elsif run.entrega != ToolRun::ENTREGUE_NO_TURNO
      return EM_ANDAMENTO
    end
    run.resultado_da_consulta
  end

  # A janela acabou. A desistência só vale sem resultado gravado; com ele, o turno entrega.
  def desistir(run, inicio)
    espera_ms = ((self.class.agora - inicio) * 1000).round
    return entregar(run) unless run.marcar_desistencia!(espera_ms: espera_ms)

    Rails.logger.info("[autonomia][tool][consulta] turno_desistiu run=#{run.id} slug=#{run.slug} espera_ms=#{espera_ms}")
    EM_ANDAMENTO
  end

  def reusada
    ToolRun.for_conversation(@turno.conversation.id).where(status: 'running', autonomia_agent_tool_id: @tool.id)
           .find_by('handle ->> ? = ?', ToolRun::CHAVE_DA_CONSULTA, @chave)
  end

  # Sob a trava da faixa, para duas passadas do mesmo pedido não abrirem duas. O job sai DEPOIS do commit.
  def abrir
    nova = false
    run = ToolRun.transaction do
      ToolRun.travar!(@turno.conversation.id, @tool.slug, faixa)
      existente = reusada
      next existente if existente

      nova = true
      aberta
    end
    ::Autonomia::Agents::Tools::HttpAssincronaJob.perform_later(run.id) if nova
    run
  end

  def aberta
    run = ToolRun.open!(agent: @agente, slug: @tool.slug, arguments: @params, marcas: marcas, scope: escopo)
    raise ActiveRecord::RecordNotUnique, "consulta #{@tool.slug} não abriu" if run.nil?

    run.promote!(expected_chunks: 0, notify_customer: false,
                 expires_at: ::Autonomia::Agents::Tools::HttpAssincronaJob.vence_em(@tool.timeout_seconds))
    run
  end

  def marcas
    { ToolRun::CHAVE_DA_CONSULTA => @chave, ToolRun::TEMPO_DA_CONSULTA => @tool.timeout_seconds,
      ToolRun::ABERTA_EM => Time.current.iso8601(3) }
  end

  def escopo
    { conversation_id: @turno.conversation.id, agent_inbox_id: @turno.agent_inbox&.id, faixa: faixa,
      origin_message_id: @turno.origin_message_id, autonomia_agent_tool_id: @tool.id }
  end

  # A faixa é o pedido (a ferramenta e os argumentos tipados, sem o turno): outro pedido corre junto; o mesmo, numa
  # mensagem nova, supersede o antigo (`ToolRun.open!`).
  def faixa
    @faixa ||= "#{ToolRun::FAIXA_DA_CONSULTA}#{::Autonomia::Insurance::Faixa::SEPARADOR}" \
               "#{Chave.resumo([@tool.id, Chave.em_ordem(@params)])[0, 16]}"
  end
end
