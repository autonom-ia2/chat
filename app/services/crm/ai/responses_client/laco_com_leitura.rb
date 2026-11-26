# O LAÇO DE FERRAMENTAS COM A LEITURA DO MEIO DO TURNO (#3225). Só roda quando quem chama passa `leitura:` ao
# `create_with_tool_executor` (o atendimento com a flag `agente_le_no_meio_do_turno`, `Operate::LeituraNoTurno`); sem ela,
# o laço e as idas são os de sempre, byte a byte.
#
# A leitura entra em dois pontos:
# - NA RODADA DE FERRAMENTAS, antes de despachar (para a mensagem nova já estar com o turno quando a ferramenta conferir
#   se ele foi superado) e depois (o que chegou durante a ferramenta). O que chegou vai depois das saídas da rodada.
#   Se as rodadas acabaram, a ida seguinte ganha ferramenta de novo, e isso conta como uma volta: a mensagem nova pode
#   mudar o pedido ("são 3 pessoas").
# - ANTES DE ENVIAR: o modelo respondeu. Chegou algo, o rascunho volta como fala do agente (só o texto), com o aviso e o
#   que chegou, e o laço dá mais uma volta com ferramenta (uma rodada e, se ele chamar, o fechamento).
#
# Quem limita é a leitura (as voltas, `LeituraNoTurno::MAX_VOLTAS`), e o relógio do laço (`max_segundos`): esgotado, ela
# não lê mais. Agente sem ferramenta também passa por aqui: as idas vão sem ferramenta, e a volta antes de enviar vale.
# As idas depois da primeira volta gravam o consumo com a etiqueta da leitura (`feature_da_volta`).
module Crm::Ai::ResponsesClient::LacoComLeitura
  # O pedido (fixo) e o que muda a cada ida.
  Laco = Struct.new(:model, :instructions, :schema, :reasoning_effort, :tools, :timeout, :max_segundos, :leitura,
                    :conversa, :usadas, :restantes, :comeco, keyword_init: true) do
    def esgotado? = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - comeco) > max_segundos

    # As ferramentas desta ida: só com rodada sobrando e relógio.
    def oferecidas = (tools.presence if restantes.positive? && !esgotado?)
  end

  private

  # Os mesmos argumentos e padrões do laço de sempre (`ResponsesClient#laco_de_ferramentas`), mais a leitura.
  OBRIGATORIOS = %i[model instructions schema leitura].freeze
  PADROES = { reasoning_effort: 'low', tools: nil, timeout: Crm::Ai::ResponsesClient::REQUEST_TIMEOUT,
              max_segundos: Crm::Ai::ResponsesClient::MAX_SEGUNDOS_DE_FERRAMENTA }.freeze

  def novo_laco(input:, max_rodadas: 1, **pedido)
    faltam = OBRIGATORIOS - pedido.keys
    raise ArgumentError, "missing keywords: #{faltam.join(', ')}" if faltam.any?

    Laco.new(**PADROES, **pedido, conversa: normalize_input(input), usadas: [],
                                  restantes: max_rodadas.to_i.clamp(1, Crm::Ai::ResponsesClient::MAX_RODADAS_DE_FERRAMENTA),
                                  comeco: Process.clock_gettime(Process::CLOCK_MONOTONIC))
  end

  def laco_com_leitura(laco, &)
    loop do
      oferecidas = laco.oferecidas
      payload, started_at = ida_da_leitura(laco, oferecidas)
      calls = oferecidas ? function_calls(payload) : []
      next rodada_da_leitura(laco, payload, calls, &) if calls.any?

      resultado = resposta_da_leitura(laco, payload, started_at)
      novas = laco.leitura.antes_de_enviar(resultado[:text], esgotado: laco.esgotado?)
      return resultado if novas.empty?

      dar_volta(laco, :antes_de_enviar)
      laco.conversa += novas
    end
  end

  # UMA ida ao modelo. -> [payload, started_at]. O consumo é gravado aqui, uma vez por ida (a resposta não grava de novo).
  def ida_da_leitura(laco, oferecidas)
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    operacao = operacao_da_ida(laco, oferecidas)
    body = base_body(laco.model, laco.instructions, laco.conversa, laco.schema, laco.reasoning_effort, oferecidas).merge(store: false)
    response = post_responses(body, timeout: laco.timeout, operation: operacao, started_at: started_at)
    payload = parse_raw(response, operation: operacao, model: laco.model, started_at: started_at)
    laco.usadas |= tools_used(payload)
    log_call(laco.model, laco.tools, laco.usadas, started_at)
    record_usage(payload['usage'], laco.model, laco.reasoning_effort, started_at, feature: feature_da_ida(laco))
    [payload, started_at]
  end

  # O rótulo do log: a ida sem as ferramentas que o agente tem é o fechamento, como no laço de sempre.
  def operacao_da_ida(laco, oferecidas)
    return 'responses.create' if oferecidas || laco.tools.blank?

    'responses.create.tool_result'
  end

  # A rodada de ferramentas: lê antes de despachar e depois; o que chegou entra depois das saídas.
  def rodada_da_leitura(laco, payload, calls)
    laco.restantes -= 1
    antes = laco.leitura.na_rodada(esgotado: laco.esgotado?)
    saidas = Array(yield(calls))
    depois = laco.leitura.na_rodada(esgotado: laco.esgotado?)
    laco.conversa += Array(payload['output']) + saidas + antes + depois
    dar_volta(laco, :rodada) if (antes + depois).any? && laco.restantes.zero?
  end

  def resposta_da_leitura(laco, payload, started_at)
    resultado = parse_response_payload(payload, model: laco.model, requested_tools: laco.tools, started_at: started_at,
                                                reasoning_effort: laco.reasoning_effort, registrar_uso: false)
    resultado[:tools_used] = (Array(resultado[:tools_used]) + laco.usadas).uniq
    resultado
  end

  # Uma volta: mais uma rodada com ferramenta (e o fechamento, se ele chamar).
  def dar_volta(laco, etapa)
    laco.leitura.contar_volta!(etapa)
    laco.restantes = 1
  end

  def feature_da_ida(laco)
    laco.leitura.voltas.positive? ? laco.leitura.feature_da_volta : @feature
  end
end
