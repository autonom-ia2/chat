# frozen_string_literal: true

# chat#1473 (P4, opção A) — WhatsApp entrega um anexo por mensagem: 2 ou mais são recusados com motivo, em vez de só o
# 1º sair em silêncio. Por prepend; os arquivos do Chatwoot ficam intactos. Ver app/services/rich_messages/attachment_limit.rb.
Rails.application.config.to_prepare do
  prepend_once = lambda do |klass, mod|
    klass.prepend(mod) unless klass.ancestors.include?(mod)
  end

  prepend_once.call(Base::SendOnChannelService, RichMessages::AttachmentLimitGuard)
  prepend_once.call(Api::V1::Accounts::Conversations::MessagesController, RichMessages::AttachmentLimitCheck)
end
