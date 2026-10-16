# Prepend em Whatsapp::Providers::WhatsappCloudService, por cima de RichMessages::WhatsappCloudDelivery (chat#1709): a
# Cloud API não tem enquete, então a `poll` sai como texto (RichMessages::Types::Poll#whatsapp_cloud_payload). Depois do
# envio, a mensagem ganha a marca "Enviado como texto" (chat#1555), para a bolha mostrar o que o cliente recebeu.
# RichMessages.mark_sent_as_text! nunca levanta e não marca mensagem que falhou.
module Waha::RichNative::PollCloudText
  def send_message(phone_number, message)
    result = super
    RichMessages.mark_sent_as_text!(message) if poll_rich_message?(message)
    result
  end

  private

  def poll_rich_message?(message)
    message.respond_to?(:content_attributes) &&
      message.content_attributes.to_h.dig(RichMessages::KEY, 'type') == Waha::RichNative::PollGate::TYPE
  end
end
