# Prepend em WebhookListener, por cima de RichMessages::ApiInboxWebhook (chat#1709, fase 2): na caixa WAHA comum, a
# mensagem que nasceu marcada 'native' (Waha::RichNative::ApiInboxDecision) leva ao webhook da caixa o pedido ao motor:
#   content_attributes.waha_native = { "kind": "sendList" | "sendLocation" | "sendContactVcard", "payload": {...} }
# `payload` é o corpo do endpoint sem `session` e `chatId` (o conector os põe), montado com o `content` cru e, na lista,
# `rowId` = "<id da opção>|<id da mensagem>" (Waha::RichNative.row_id). O `content` continua o texto de reserva
# (corpo + versão em texto), para um motor sem o conector customizado mandar o texto completo.
# Só no `message_created` (o envio); o `message_updated` (status, edição) vai como sempre, sem o pedido, para o conector
# não mandar de novo. Mensagem marcada 'text' ou sem marca: nada muda.
module Waha::RichNative::InboxWebhook
  CONTRACT_KEY = 'waha_native'.freeze

  private

  def rich_inbox_payload(payload, inbox)
    result = super
    return result unless result && payload[:event] == 'message_created' && inbox.channel.try(:waha_provider?)

    request = waha_native_request(payload)
    request ? result.merge(content_attributes: result[:content_attributes].merge(CONTRACT_KEY => request)) : result
  end

  def waha_native_request(payload)
    message = Message.find_by(id: payload[:id])
    return unless message && Waha::RichNative.sent_native?(message)

    request = Waha::RichNative::WahaInbox.payload_for(message, reference: message.id)&.request
    Rails.logger.error("[waha] rich native request not built message=#{message.id}") if request.nil?
    request
  end
end
