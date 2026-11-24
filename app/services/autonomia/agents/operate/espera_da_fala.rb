# QUANTO ESPERAR E QUANDO ENTRAR NA FILA (#3211). Duas decisões do turno do agente, ambas por opção do agente
# (ParidadeDaConversa), ambas desligadas por padrão:
#
# - `da_rajada` (P1, `conversa_espera_a_fala`): a espera do debounce. Desligada, é a janela de sempre
#   (Config.debounce_seconds_for). Ligada, é o fim previsto da fala anterior menos agora, preso entre ESPERA_MINIMA e
#   ESPERA_MAXIMA; sem fim previsto, ESPERA_MINIMA. Assim a pergunta junta toda a rajada que o cliente mandou enquanto o
#   agente ainda falava.
# - `na_fila?` (P2, `conversa_em_fila`): o turno novo deve esperar porque outro turno está falando. Só vale até o prazo
#   da marca do debounce (`at` + `espera_ms`) mais TETO_DA_FILA: passado isso o turno segue mesmo com a marca ocupada, para
#   uma marca presa nunca travar a conversa. Sem a marca do debounce, ou sem `at`, não há prazo, então nunca fila.
module Autonomia::Agents::Operate::EsperaDaFala
  ESPERA_MINIMA = 1.second
  ESPERA_MAXIMA = 180.seconds
  INTERVALO_DA_FILA = 2.seconds
  TETO_DA_FILA = 150.seconds

  module_function

  def da_rajada(agent:, conversation_id:, agora: Time.current)
    return ::Autonomia::Agents::Config.debounce_seconds_for(agent) unless ::Autonomia::Agents::ParidadeDaConversa.espera_a_fala?(agent)

    fim = ::Autonomia::Agents::Operate::FalaEmCurso.fim_previsto(conversation_id)
    return ESPERA_MINIMA if fim.blank?

    (fim - agora).clamp(ESPERA_MINIMA.to_f, ESPERA_MAXIMA.to_f).seconds
  end

  def na_fila?(agent:, conversation:, message_id:, agora: Time.current)
    return false unless ::Autonomia::Agents::ParidadeDaConversa.em_fila?(agent)
    return false unless ::Autonomia::Agents::Operate::FalaEmCurso.ocupada_por_outro?(conversation.id, message_id)

    prazo = prazo_da_fila(conversation)
    prazo.present? && agora < prazo
  end

  # O instante em que a fila desiste: a marca do debounce (`at` + `espera_ms`) mais o teto da fila. nil sem prazo.
  def prazo_da_fila(conversation)
    marca = conversation.additional_attributes.to_h[::Autonomia::Agents::Operate::ReplyJob::DEBOUNCE_KEY]
    return unless marca.is_a?(Hash) && marca['at'].present?

    Time.zone.at(marca['at'].to_f + (marca['espera_ms'].to_i / 1000.0)) + TETO_DA_FILA
  end
  private_class_method :prazo_da_fila
end
