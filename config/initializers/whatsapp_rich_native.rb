# frozen_string_literal: true

# chat#1709 — mensagem rica nativa pelo WhatsApp API, atrás da flag `whatsapp_rich_native`: plano B do WhatsApp Híbrido
# (fase 1) e caixa WAHA comum, enviada pelo conector do WAHA (fase 2, Waha::RichNative::WahaInbox).
# Por prepend: WebTransport, RichMessages e o serviço de recebimento do Chatwoot ficam intactos. No core, só duas linhas
# no padrão do `whatsapp_api_reply` (jbuilder da conversa e EventDataPresenter). Ver app/services/whatsapp_hybrid/rich_native.rb.
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

  # Fase 2: decisão na criação, pedido no webhook da caixa, trava contra forja e volta da escolha do cliente.
  # O webhook entra DEPOIS de RichMessages::ApiInboxWebhook (config/initializers/rich_messages.rb roda antes), para
  # ficar por cima dele e acrescentar o pedido ao que ele monta.
  unless RichMessages::ApiInboxSentAsText.singleton_class <= Waha::RichNative::ApiInboxDecision
    RichMessages::ApiInboxSentAsText.singleton_class.prepend(Waha::RichNative::ApiInboxDecision)
  end
  WebhookListener.prepend(Waha::RichNative::InboxWebhook) unless WebhookListener <= Waha::RichNative::InboxWebhook
  unless Api::V1::Accounts::Conversations::MessagesController <= Waha::RichNative::ForgeryGuard
    Api::V1::Accounts::Conversations::MessagesController.prepend(Waha::RichNative::ForgeryGuard)
  end
  Message.before_create Waha::RichNative::ListReply if Message._create_callbacks.none? { |callback| callback.filter == Waha::RichNative::ListReply }
end
