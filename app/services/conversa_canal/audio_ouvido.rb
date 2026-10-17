# Áudio ouvido (microfone azul) do WhatsApp (#1702). A Cloud API manda o status `played` na primeira vez que o aparelho
# do cliente toca a nota de voz:
# https://developers.facebook.com/documentation/business-messaging/whatsapp/webhooks/reference/messages/status.md
# O enum de status do Chatwoot (sent/delivered/read/failed) não muda: o Messages::StatusUpdateService continua
# descartando `played`, e aqui a hora fica em `content_attributes.played_at` da mensagem enviada. Só a primeira conta.
module ConversaCanal::AudioOuvido
  CHAVE = 'played_at'.freeze

  module_function

  def registrar(message, status)
    return if message.nil? || !message.outgoing?

    message.with_lock do
      attrs = message.content_attributes.to_h
      next if attrs[CHAVE].present?

      message.update!(content_attributes: attrs.merge(CHAVE => quando(status).iso8601))
    end
  end

  def quando(status)
    segundos = status[:timestamp].to_i
    segundos.positive? ? Time.zone.at(segundos) : Time.current
  end
end
