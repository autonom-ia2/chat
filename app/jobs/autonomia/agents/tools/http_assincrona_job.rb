# A PASSADA DA FERRAMENTA HTTP ASSÍNCRONA (#1430): a cadastrada com tempo acima de `Tool::LIMIAR_ASSINCRONO`, aceita no
# turno por `Tools::ConsultaAssincrona` e despachada pelo `AsyncDispatcher`.
#
# UMA chamada, sem poll: o sistema de fora responde na mesma requisição, só que demora. Por isso o job roda na fila
# própria (`AgentToolsQueue`), com threads só dela: uma conta com o sistema lento não ocupa as filas das outras.
#
# A ferramenta é resolvida pelo id gravado na linha, nunca pelo slug (`Registry`): o slug de uma HTTP pode ser o de uma
# nativa, e o `AsyncRunJob` cotaria na Lia. A chamada leva a Idempotency-Key gravada no aceite e o tempo da ferramenta.
#
# O DESFECHO é o texto que o modelo leria no síncrono — a resposta com o teto de saída (`Bound#cabendo`), ou a saída
# de recusa (`Bound#texto_da_recusa_http`) —, gravado na linha, e o evento (`consulta_concluida` ou `consulta_falhou`):
# quem fala com o cliente é o agente, num turno de evento. A consulta supersedida no meio grava o resultado e não fala.
#
# DEPLOY NO MEIO: o worker morre e o job não volta. Quem recupera é o `ReapStaleRunsJob`, uma vez (`reenfileirar`), com
# a mesma chave; na segunda, `abandonar`.
class Autonomia::Agents::Tools::HttpAssincronaJob < ApplicationJob
  FILA = AgentToolsQueue::FILA.to_sym
  queue_as FILA

  ToolRun = ::Autonomia::Agents::ToolRun
  Evento = ::Autonomia::Agents::Tools::Evento
  # O prazo da linha passa do tempo da ferramenta por esta folga: a espera na fila e a abertura da conexão. O varredor
  # ainda soma a dele (`ReapStaleRunsJob::GRACE`) antes de reenfileirar. Folga de desenho, não medida.
  FOLGA = 2.minutes

  def self.vence_em(tool)
    (tool&.timeout_seconds || ::Autonomia::Agents::Tool::TEMPO_PADRAO).seconds.from_now + FOLGA
  end

  # A segunda chance do varredor: -> true quando enfileirou.
  def self.reenfileirar(run)
    return false unless run.reenfileirar_consulta!(expires_at: vence_em(run.ferramenta))

    perform_later(run.id)
    true
  end

  # A consulta que morreu duas vezes: falha, e o agente diz que não conseguiu. Só a que ainda roda: o resultado de uma
  # passada que acabou de fechar não é trocado por este.
  def self.abandonar(run)
    return unless run.running?

    encerrar(run, 'failed', 'execucao_abandonada', ::Autonomia::Agents::Tools::Recusa.saida('execucao_abandonada'))
  end

  # O resultado vai à linha mesmo que ela já não rode. Só a que roda fala: o evento ANTES do `finish!`, porque o slot
  # dele só é adquirido em linha viva (`Evento.disparar`).
  def self.encerrar(run, status, codigo, saida)
    run.gravar_resultado!(saida)
    return Rails.logger.info("[autonomia][tool][http_assincrona] run=#{run.id} status=#{run.status} sem evento") unless run.running?

    Evento.disparar(run, status == 'done' ? Evento::CONSULTA_CONCLUIDA : Evento::CONSULTA_FALHOU)
    run.finish!(status, failure_code: codigo)
  end

  def perform(run_id)
    run = ToolRun.find_by(id: run_id)
    return if run.blank? || !run.running? || !run.consulta_http?

    tool = ferramenta(run)
    if tool.nil?
      return self.class.encerrar(run, 'failed', 'ferramenta_indisponivel', ::Autonomia::Agents::Tools::Recusa.saida('ferramenta_indisponivel'))
    end
    return if bloqueada?(run)

    saida, falha = chamar(run, tool)
    self.class.encerrar(run, falha ? 'failed' : 'done', falha, saida)
  end

  private

  # Desligada ou apagada depois do aceite: indisponível. Do mesmo agente da linha, sempre.
  def ferramenta(run)
    ::Autonomia::Agents::Tool.enabled.find_by(id: run.autonomia_agent_tool_id, autonomia_agent_id: run.autonomia_agent_id)
  end

  # O operador puxou o freio depois do aceite (conta, agente, allowlist), ou a conversa mudou de dono: para sem chamar e
  # sem falar, como o `AsyncRunJob`.
  def bloqueada?(run)
    vinculo = ::Autonomia::Agents::Operate.authorized_agent_inbox(run.conversation)
    codigo = if vinculo.blank? then 'nao_autorizado'
             elsif run.agent_inbox_id.present? && vinculo.id != run.agent_inbox_id then 'vinculo_mudou'
             end
    return false if codigo.nil?

    run.finish!('blocked', failure_code: codigo)
    true
  end

  # -> [o texto do desfecho, o código da falha ou nil]. A conexão do banco é devolvida ao pool antes da chamada: a
  # espera é longa, e a thread não precisa segurar uma conexão enquanto isso.
  def chamar(run, tool)
    bound = ::Autonomia::Agents::Tools::Bound.new(agent: run.agent, record: tool)
    ActiveRecord::Base.connection_handler.clear_active_connections!
    [bound.cabendo(executor(run, tool).call), nil]
  rescue ::Autonomia::Agents::Tools::HttpExecutor::Error => e
    [bound.texto_da_recusa_http(e), bound.categoria_da_recusa_http(e)]
  rescue StandardError => e
    Rails.logger.warn("[autonomia][tool][http_assincrona] run=#{run.id} #{e.class}")
    [::Autonomia::Agents::Tools::Recusa.saida('tool_execution_error'), 'tool_execution_error']
  end

  def executor(run, tool)
    ::Autonomia::Agents::Tools::HttpExecutor.new(tool: tool, params: run.arguments, chave: run.handle.to_h[ToolRun::CHAVE_DA_CONSULTA],
                                                 segundos: tool.timeout_seconds)
  end
end
