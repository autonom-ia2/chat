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
  # Por cima de RichMessages::RetryKeepsFormat (prepend antes, em config/initializers/rich_messages.rb).
  unless Api::V1::Accounts::Conversations::MessagesController <= Waha::RichNative::RetryAsText
    Api::V1::Accounts::Conversations::MessagesController.prepend(Waha::RichNative::RetryAsText)
  end
  if Message._create_callbacks.none? { |callback| callback.filter == Waha::RichNative::ContractGuard }
    Message.before_create Waha::RichNative::ContractGuard
  end
  Message.before_create Waha::RichNative::ListReply if Message._create_callbacks.none? { |callback| callback.filter == Waha::RichNative::ListReply }

  # Fase 3: enquete (tipo `poll` só com a flag; na Cloud sai como texto), e a volta do conector c2y-rich-2 (voto,
  # ligação, mensagem desconhecida, reação e edição: Waha::RichNative::Inbound).
  RichMessages.singleton_class.prepend(Waha::RichNative::PollGate) unless RichMessages.singleton_class <= Waha::RichNative::PollGate
  unless Whatsapp::Providers::WhatsappCloudService <= Waha::RichNative::PollCloudText
    Whatsapp::Providers::WhatsappCloudService.prepend(Waha::RichNative::PollCloudText)
  end
  Message.before_create Waha::RichNative::Inbound if Message._create_callbacks.none? { |callback| callback.filter == Waha::RichNative::Inbound }
end

# Flag ligada numa conta: a capacidade dos motores é lida na hora, sem esperar o cron (Waha::RichNative::ColdStart).
# Registrado DEPOIS da inicialização (e de novo a cada recarga de código): carregar `Account` dentro do `to_prepare` da
# partida carrega junto o `Team` (CacheKeys), cuja validação lê o I18n na carga da classe, antes de as traduções
# existirem (a mensagem de "presença" ficaria "Translation missing").
register_rich_native_cold_start = lambda do
  if Account._commit_callbacks.none? { |callback| callback.filter == Waha::RichNative::ColdStart }
    Account.after_update_commit Waha::RichNative::ColdStart
  end
end
Rails.application.config.after_initialize { register_rich_native_cold_start.call }
Rails.application.config.to_prepare { register_rich_native_cold_start.call if Rails.application.initialized? }
