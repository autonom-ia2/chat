# frozen_string_literal: true

# chat#1709 — mensagem rica nativa no plano B do WhatsApp Híbrido, atrás da flag `whatsapp_rich_native`.
# Tudo por prepend; WebTransport, RichMessages e o serviço do Chatwoot ficam intactos. Ver
# app/services/whatsapp_hybrid/rich_native.rb.
Rails.application.config.to_prepare do
  unless WhatsappHybrid::WebTransport <= WhatsappHybrid::RichNative::Transport
    WhatsappHybrid::WebTransport.prepend(WhatsappHybrid::RichNative::Transport)
  end
  unless RichMessages.singleton_class <= WhatsappHybrid::RichNative::DeliveryMode
    RichMessages.singleton_class.prepend(WhatsappHybrid::RichNative::DeliveryMode)
  end
  unless Whatsapp::IncomingMessageBaseService <= WhatsappHybrid::RichNative::ReplyLink
    Whatsapp::IncomingMessageBaseService.prepend(WhatsappHybrid::RichNative::ReplyLink)
  end
end
