# Prepend em Api::V1::Accounts::Conversations::MessagesController, por cima de RichMessages::RetryKeepsFormat (chat#1709,
# fase 2): o reenvio numa caixa WAHA comum sai pelo `message_updated` do webhook da caixa, que nunca leva o pedido ao
# motor (Waha::RichNative::InboxWebhook): o cliente recebe o texto de reserva. A marca acompanha: a mensagem que tinha
# saído nativa passa a 'text' (com o texto enviado), para a bolha mostrar o que o cliente recebeu.
module Waha::RichNative::RetryAsText
  private

  def retry_content_attributes
    attributes = super
    return attributes unless attributes.to_h[RichMessages::SENT_AS_KEY] == Waha::RichNative::SENT_AS && waha_inbox_retry?

    attributes.merge(RichMessages.sent_as_text_attributes(message))
  end

  def waha_inbox_retry?
    @conversation.inbox.channel_type == 'Channel::Api' && @conversation.inbox.channel.waha_provider?
  end
end
