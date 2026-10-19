# Prepend na classe singleton de RichMessages::ApiInboxSentAsText (chat#1709, fase 2): a decisão ÚNICA da caixa WAHA
# comum, no `before_create` da mensagem, antes do INSERT (o `message_created` sai uma vez só, já com a marca).
# Nativa (Waha::RichNative::WahaInbox.native_for?): grava `rich_message_sent_as: 'native'`. Senão, o original grava
# 'text', como no #1555. A entrega (RichMessages::ApiInboxWebhook + Waha::RichNative::InboxWebhook) lê só esta marca:
# se o cache da capacidade do motor mudar entre a criação e a entrega, a marca e o pedido continuam iguais.
# Nunca interrompe a criação: erro aqui segue o caminho do texto.
module Waha::RichNative::ApiInboxDecision
  def before_create(message)
    return super unless waha_native?(message)

    message.content_attributes = message.content_attributes.merge(RichMessages::SENT_AS_KEY => Waha::RichNative::SENT_AS)
  end

  def waha_native?(message)
    Waha::RichNative::WahaInbox.native_for?(message)
  rescue StandardError => e
    Rails.logger.error("[waha] rich native decision #{e.class}")
    false
  end
end
