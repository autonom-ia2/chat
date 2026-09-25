# Registro de eventos da Prospecção (#732 item 13, ENRIQ-60): uma linha no log do Rails por evento, com prefixo fixo e
# o payload em JSON, sem tabela. O Orth grava os eventos do enriquecimento; aqui a decisão de 25/09 foi o log.
#
# Só entram o nome do evento, o lead e a conta pelo id, a origem do número (google ou site), o desfecho e o motivo em
# código fechado. Telefone, e-mail, chat do WhatsApp, token e chave nunca entram: o motivo de uma exceção é o nome da
# classe, não a mensagem, que pode carregar a URL com o número ou a chave. Chave fora das previstas é recusada.
module Autonomia::Prospecting::EventLog
  PREFIX = '[Autonomia::Prospecting::Event]'.freeze
  LEVELS = %i[info warn].freeze
  DETAIL_KEYS = %i[source status].freeze
  REASON_MAX_LENGTH = 80

  module_function

  def emit(event, lead:, reason: nil, level: :info, **details)
    unknown = details.keys - DETAIL_KEYS
    raise ArgumentError, "chave fora do registro de eventos: #{unknown.join(', ')}" if unknown.any?

    payload = { event: event.to_s, lead_id: lead&.id, account_id: lead&.account_id, reason: reason_code(reason) }
              .merge(details.transform_values { |value| value&.to_s })
              .compact
    Rails.logger.public_send(LEVELS.include?(level) ? level : :info, "#{PREFIX} #{payload.to_json}")
  end

  def reason_code(reason)
    return if reason.nil?
    return reason.class.name if reason.is_a?(Exception)

    reason.to_s.truncate(REASON_MAX_LENGTH)
  end
end
