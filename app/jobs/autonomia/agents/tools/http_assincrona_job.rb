# A CHAMADA DA CONSULTA HTTP EM SEGUNDO PLANO (#1430, desenho D). Quem abre a execução e a enfileira é o turno
# (`Tools::ConsultaNoTurno`), que espera por ela até a janela dele.
#
# UMA chamada, sem poll, na fila própria (`AgentToolsQueue`): uma conta com o sistema lento não ocupa as filas das
# outras. Sem retry do Sidekiq: uma nova tentativa automática chamaria o sistema de fora de novo. A ordem que protege a
# chamada única, a mesma do `SUBMITTED_KEY` da Lia:
#   1. reivindica a linha: renova o prazo com o tempo gravado na abertura e anota a espera na fila;
#   2. com o resultado já gravado (reentrada), só fecha;
#   3. confere a ferramenta e a autorização;
#   4. marca `chamada_feita` por compare-and-set — só em linha viva, sem chamada e sem resultado. Quem não marca não
#      chama: a superada antes de começar e a reentrada depois da marca param aqui;
#   5. solta a conexão do banco, chama com a chave e o tempo da abertura;
#   6. grava o resultado uma vez (higienizado, o mesmo texto do síncrono), com conexão nova;
#   7. fecha: o evento só sai se o turno desistiu (`ENTREGA`), e sai ANTES do `finish!`, porque o slot dele só é
#      adquirido em linha viva.
#
# A ferramenta é resolvida pelo id gravado na linha, nunca pelo slug.
#
# DEPLOY NO MEIO: o worker morre e o job não volta. Quem recupera é o `ReapStaleRunsJob`, uma vez (`reenfileirar`, que
# tira a `chamada_feita` e manda a mesma chave); na segunda, `abandonar`.
class Autonomia::Agents::Tools::HttpAssincronaJob < ApplicationJob
  FILA = AgentToolsQueue::FILA.to_sym
  queue_as FILA
  sidekiq_options retry: false

  ToolRun = ::Autonomia::Agents::ToolRun
  Evento = ::Autonomia::Agents::Tools::Evento
  # O prazo da linha passa do tempo da ferramenta por esta folga: a espera na fila e a abertura da conexão. O varredor
  # ainda soma a dele (`ReapStaleRunsJob::GRACE`) antes de reenfileirar. Folga de desenho, não medida.
  FOLGA = 2.minutes

  def self.vence_em(segundos)
    segundos.to_i.seconds.from_now + FOLGA
  end

  # A segunda chance do varredor: -> true quando enfileirou.
  def self.reenfileirar(run)
    return false unless run.reenfileirar_consulta!(expires_at: vence_em(run.handle.to_h.fetch(ToolRun::TEMPO_DA_CONSULTA)))

    perform_later(run.id)
    true
  end

  # A consulta que morreu duas vezes: falha, e o agente diz que não conseguiu. O turno já foi embora há muito: sem marca
  # de entrega, quem fala é o evento.
  def self.abandonar(run)
    return unless run.running?

    run.marcar_desistencia!(espera_ms: nil)
    run.gravar_resultado!(::Autonomia::Agents::Tools::Recusa.saida('execucao_abandonada'), sucesso: false, codigo: 'execucao_abandonada',
                                                                                           api_ms: nil)
    fechar(run.reload)
  end

  # O evento só com a desistência do turno, e antes do `finish!`.
  def self.fechar(run)
    status = run.resultado_ok? ? 'done' : 'failed'
    if run.entrega == ToolRun::DESISTIU_DO_TURNO
      Evento.disparar(run, run.resultado_ok? ? Evento::CONSULTA_CONCLUIDA : Evento::CONSULTA_FALHOU)
    end
    run.finish!(status, failure_code: run.resultado_ok? ? nil : run.handle.to_h[ToolRun::CODIGO_DA_CONSULTA])
  end

  def perform(run_id)
    inicio = agora
    run = consulta_viva(run_id)
    return unless run && reivindicar(run)
    return self.class.fechar(run) if run.resultado_gravado?

    tool = ferramenta(run)
    return indisponivel(run) if tool.nil?
    return if bloqueada?(run)

    chamar_uma_vez(run, tool, inicio)
  end

  private

  def agora
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def consulta_viva(run_id)
    run = ToolRun.find_by(id: run_id)
    run if run&.running? && run.consulta_http?
  end

  def reivindicar(run)
    aberta_em = Time.zone.parse(run.handle.to_h[ToolRun::ABERTA_EM].to_s)
    fila_ms = aberta_em && ((Time.current - aberta_em) * 1000).round
    run.reivindicar!(expires_at: self.class.vence_em(run.handle.to_h.fetch(ToolRun::TEMPO_DA_CONSULTA)), fila_ms: fila_ms)
  end

  def chamar_uma_vez(run, tool, inicio)
    chave = run.handle.to_h.fetch(ToolRun::CHAVE_DA_CONSULTA)
    return log(run, 'chamada_ja_feita') unless run.marcar_chamada!

    banco_antes_ms = ms_desde(inicio)
    ::Autonomia::Agents::Tools::ConexaoDoBanco.soltar
    saida, codigo, api_ms = chamar(run, tool, chave)
    depois = agora
    gravou = run.gravar_resultado!(saida, sucesso: codigo.nil?, codigo: codigo, api_ms: api_ms)
    run.reload
    run.running? ? self.class.fechar(run) : superada(run, gravou)
    log(run, "fim fila_ms=#{run.handle[ToolRun::FILA_MS]} api_ms=#{api_ms} banco_antes_ms=#{banco_antes_ms} " \
             "banco_depois_ms=#{ms_desde(depois)}")
  end

  # -> [o texto do desfecho, o código da falha ou nil, o tempo da API]. Só os erros esperados da chamada viram desfecho
  # (o executor já traduz rede, tempo, HTTP e modelo para `HttpExecutor::Error`); o defeito nosso sobe, registrado.
  def chamar(run, tool, chave)
    bound = ::Autonomia::Agents::Tools::Bound.new(agent: run.agent, record: tool)
    comeco = agora
    texto = executor(run, tool, chave).call
    [bound.cabendo(texto), nil, ms_desde(comeco)]
  rescue ::Autonomia::Agents::Tools::HttpExecutor::Error => e
    [bound.texto_da_recusa_http(e), bound.categoria_da_recusa_http(e), ms_desde(comeco)]
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: run.account).capture_exception
    raise
  end

  def executor(run, tool, chave)
    ::Autonomia::Agents::Tools::HttpExecutor.new(tool: tool, params: run.arguments, chave: chave, higienizar: true,
                                                 segundos: run.handle.to_h.fetch(ToolRun::TEMPO_DA_CONSULTA))
  end

  # A consulta trocada por uma mais nova enquanto chamava: o resultado fica gravado e não é falado. Se o sistema de fora
  # fez o pedido (2xx), quem atende fica sabendo.
  def superada(run, gravou)
    return unless gravou && run.resultado_ok?

    ::Autonomia::Agents::Operate::AvisoAoAtendente.consulta_antiga(run)
  end

  # Desligada ou apagada depois da abertura. Da mesma conta, pelo id; a ferramenta pode ser de um ajudante.
  def ferramenta(run)
    ::Autonomia::Agents::Tool.enabled.find_by(id: run.autonomia_agent_tool_id, account_id: run.account_id)
  end

  def indisponivel(run)
    run.gravar_resultado!(::Autonomia::Agents::Tools::Recusa.saida('ferramenta_indisponivel'), sucesso: false,
                                                                                               codigo: 'ferramenta_indisponivel', api_ms: nil)
    self.class.fechar(run.reload)
  end

  # O operador puxou o freio depois da abertura (conta, agente, allowlist), ou a conversa mudou de dono: para sem chamar
  # e sem falar, como o `AsyncRunJob`.
  def bloqueada?(run)
    vinculo = ::Autonomia::Agents::Operate.authorized_agent_inbox(run.conversation)
    codigo = if vinculo.blank? then 'nao_autorizado'
             elsif run.agent_inbox_id.present? && vinculo.id != run.agent_inbox_id then 'vinculo_mudou'
             end
    return false if codigo.nil?

    run.finish!('blocked', failure_code: codigo)
    true
  end

  def ms_desde(comeco)
    ((agora - comeco) * 1000).round
  end

  def log(run, texto)
    Rails.logger.info("[autonomia][tool][http_assincrona] run=#{run.id} #{texto}")
  end
end
