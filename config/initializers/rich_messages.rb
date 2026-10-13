# frozen_string_literal: true

# chat#1473 — Envios ricos pelo painel (`content_attributes.rich_message`). Tudo no fork por prepend; os arquivos
# do Chatwoot ficam intactos. Ver app/services/rich_messages.rb.
# Tipo novo que precisar de outro prepend cria o próprio initializer; este arquivo não é editado.

# `rich_message` leva endereço e, em outros tipos, dados de formulário: não vai para o log de parâmetros
# (o Lograge, quando ligado, registra esses mesmos parâmetros já filtrados).
Rails.application.config.filter_parameters += [:rich_message]

Rails.application.config.to_prepare do
  prepend_once = lambda do |klass, mod|
    klass.prepend(mod) unless klass.ancestors.include?(mod)
  end

  prepend_once.call(Base::SendOnChannelService, RichMessages::SendGuard)
  prepend_once.call(Whatsapp::Providers::WhatsappCloudService, RichMessages::WhatsappCloudDelivery)
  prepend_once.call(Message, RichMessages::OutgoingText)
  prepend_once.call(WebhookListener, RichMessages::ApiInboxWebhook)
  prepend_once.call(Api::V1::Accounts::Conversations::MessagesController, RichMessages::RetryKeepsFormat)
  prepend_once.call(Api::V1::Accounts::Conversations::MessagesController, RichMessages::CreationCheck)
end
