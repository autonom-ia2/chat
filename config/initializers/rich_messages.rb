# frozen_string_literal: true

# chat#1473 — Envios ricos pelo painel (`content_attributes.rich_message`). Tudo no fork por prepend; os arquivos
# do Chatwoot ficam intactos. Ver app/services/rich_messages.rb.
Rails.application.config.to_prepare do
  prepend_once = lambda do |klass, mod|
    klass.prepend(mod) unless klass.ancestors.include?(mod)
  end

  prepend_once.call(Base::SendOnChannelService, RichMessages::SendGuard)
  prepend_once.call(Whatsapp::Providers::WhatsappCloudService, RichMessages::WhatsappCloudDelivery)
  prepend_once.call(Message, RichMessages::OutgoingText)
  prepend_once.call(Api::V1::Accounts::Conversations::MessagesController, RichMessages::RetryKeepsFormat)
end
