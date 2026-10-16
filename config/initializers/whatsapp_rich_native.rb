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
end

# Depois do bloco acima (os `to_prepare` rodam na ordem): o Inbound fica depois do ContractGuard e do ListReply.
Rails.application.config.to_prepare do
  # Fase 3: enquete (tipo `poll` só com a flag; na Cloud sai como texto), e a volta do conector c2y-rich-2 (voto,
  # ligação, mensagem desconhecida, reação e edição: Waha::RichNative::Inbound).
  RichMessages.singleton_class.prepend(Waha::RichNative::PollGate) unless RichMessages.singleton_class <= Waha::RichNative::PollGate
  unless Whatsapp::Providers::WhatsappCloudService <= Waha::RichNative::PollCloudText
    Whatsapp::Providers::WhatsappCloudService.prepend(Waha::RichNative::PollCloudText)
  end
  Message.before_create Waha::RichNative::Inbound if Message._create_callbacks.none? { |callback| callback.filter == Waha::RichNative::Inbound }
  # O `in_reply_to` do conector antes de o Chatwoot apagar o que é de outra conversa (reação/edição numa conversa nova).
  if Message._validation_callbacks.none? { |callback| callback.filter == Waha::RichNative::Inbound::ReplyTarget }
    Message.before_validation Waha::RichNative::Inbound::ReplyTarget, on: :create
  end
  # Texto no formato do WhatsApp e foto/vídeo como mídia: o mais externo do webhook da caixa (depois do InboxWebhook).
  WebhookListener.prepend(Waha::RichNative::OutgoingHints) unless WebhookListener <= Waha::RichNative::OutgoingHints
  # Reação e edição gravadas não mandam `message_updated` ao conector (ele o leria como pedido de reenvio).
  WebhookListener.prepend(Waha::RichNative::SilentUpdate) unless WebhookListener <= Waha::RichNative::SilentUpdate
  # A atividade escondida (`c2y_hidden`) não sobe a conversa na lista nem vai às integrações da conta.
  Message.prepend(Waha::RichNative::HiddenActivity) unless Message <= Waha::RichNative::HiddenActivity
  HookListener.prepend(Waha::RichNative::HiddenActivityHooks) unless HookListener <= Waha::RichNative::HiddenActivityHooks
end

Rails.application.config.to_prepare do
  # Fase 3, plano B do Híbrido (web_transport.rb e echo_reconciler_extension.rb intocados): citação no envio, foto
  # como foto, apagar para todos e o voto da enquete de volta (assinatura `poll.vote` com a flag).
  WhatsappHybrid::WebTransport.prepend(WhatsappHybrid::RichNative::Quote) unless WhatsappHybrid::WebTransport <= WhatsappHybrid::RichNative::Quote
  unless WhatsappHybrid::WebTransport <= WhatsappHybrid::RichNative::MediaAsMedia
    WhatsappHybrid::WebTransport.prepend(WhatsappHybrid::RichNative::MediaAsMedia)
  end
  unless WhatsappHybrid::SessionManager <= WhatsappHybrid::RichNative::PollVoteEvents
    WhatsappHybrid::SessionManager.prepend(WhatsappHybrid::RichNative::PollVoteEvents)
  end
  unless Webhooks::WhatsappHybridController <= WhatsappHybrid::RichNative::PollVoteWebhook
    Webhooks::WhatsappHybridController.prepend(WhatsappHybrid::RichNative::PollVoteWebhook)
  end
  if Message._commit_callbacks.none? { |callback| callback.filter == WhatsappHybrid::RichNative::RevokeOnDelete }
    Message.after_update_commit WhatsappHybrid::RichNative::RevokeOnDelete
  end
  # O voto do plano B não abre a janela de 24 h da Cloud; o `unsupported` da Meta sobre a enquete nossa não vira bolha.
  unless Conversations::MessageWindowService <= WhatsappHybrid::RichNative::WindowNeutral
    Conversations::MessageWindowService.prepend(WhatsappHybrid::RichNative::WindowNeutral)
  end
  unless Whatsapp::IncomingMessageBaseService <= WhatsappHybrid::RichNative::PollVoteCloudEcho
    Whatsapp::IncomingMessageBaseService.prepend(WhatsappHybrid::RichNative::PollVoteCloudEcho)
  end
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

Rails.application.config.to_prepare do
  # Rodada 2: as marcas do anexo (voz, figurinha, visualização única) vão ao painel.
  Attachment.prepend(Waha::RichNative::AttachmentMeta) unless Attachment <= Waha::RichNative::AttachmentMeta
end

Rails.application.config.to_prepare do
  # Rodada 2: o recibo "ouvido" do áudio (parâmetro `c2y_played_at` do conector no PATCH de status) e o aviso de
  # mensagens temporárias, criado depois da mensagem do cliente.
  unless Api::V1::Accounts::Conversations::MessagesController <= Waha::RichNative::PlayedReceipt
    Api::V1::Accounts::Conversations::MessagesController.prepend(Waha::RichNative::PlayedReceipt)
  end
  if Message._commit_callbacks.none? { |callback| callback.filter == Waha::RichNative::Inbound::Context }
    Message.after_create_commit Waha::RichNative::Inbound::Context
  end
  # A imagem do cartão de prévia do link vira cópia da instalação ANTES de qualquer decisão de envio (a da caixa WAHA
  # comum, RichMessages::ApiInboxSentAsText, é registrada num initializer anterior): por isso `prepend: true`.
  # A localização que virou cartão de mapa (`content` nil) chega à IA Autonomia como texto.
  unless Autonomia::Agents::Operate::Responder <= Waha::RichNative::ResponderLocation
    Autonomia::Agents::Operate::Responder.prepend(Waha::RichNative::ResponderLocation)
  end
  if Message._create_callbacks.none? { |callback| callback.filter == Waha::RichNative::PreviewImage }
    Message.before_create Waha::RichNative::PreviewImage, prepend: true
  end
end
