# Callback `before_create` de Message (chat#1555), registrado em config/initializers/rich_messages_sent_as_text.rb.
# A caixa Channel::Api não tem serviço de envio: quem entrega é o webhook dela, montado com o evento
# `message_created` (RichMessages::ApiInboxWebhook manda corpo + versão em texto). Gravar a marca depois disso
# geraria um `message_updated`, que o webhook da caixa também entrega: o cliente receberia a mensagem de novo.
# Por isso a mensagem já nasce marcada, antes do INSERT, e o `message_created` sai uma vez só, com a marca.
# Só marca o que o webhook de fato entrega, com as mesmas travas do WebhookListener#deliver_api_inbox_webhooks:
# mensagem que vai ao canal, caixa com endereço de webhook, conversa sem a trava de transmissão
# (Autonomia::Channels::BroadcastGuard) e formato sem erro (com erro, o webhook recusa e a mensagem fica `failed`).
# Mensagem sem `rich_message` sai sem consulta. Nunca interrompe a criação. O reenvio mantém a marca
# (RichMessages::RetryKeepsFormat), porque este callback não roda de novo.
class RichMessages::ApiInboxSentAsText
  def self.before_create(message)
    return unless RichMessages.format_lost_as_text?(message) && RichMessages.goes_to_channel?(message)
    return unless delivered_by_inbox_webhook?(message)
    return if RichMessages.error_for(message)

    message.content_attributes = message.content_attributes.merge(RichMessages.sent_as_text_attributes(message))
  rescue StandardError => e
    Rails.logger.error("[rich_messages] api_inbox_sent_as_text #{e.class}")
  end

  def self.delivered_by_inbox_webhook?(message)
    inbox = message.inbox
    inbox.channel_type == 'Channel::Api' && inbox.channel.webhook_url.present? &&
      !::Autonomia::Channels::BroadcastGuard.blocked_conversation?(message.conversation)
  end
end
