# frozen_string_literal: true

# #1702 — Figurinha do WhatsApp: guardada como foto com a marca `meta.is_sticker` e mostrada solta, como no app.
# Prepend próprio; os arquivos do Chatwoot ficam intactos. Ver ConversaCanal::FigurinhaRecebida.
Rails.application.config.to_prepare do
  unless Whatsapp::IncomingMessageBaseService <= ConversaCanal::FigurinhaRecebida
    Whatsapp::IncomingMessageBaseService.prepend(ConversaCanal::FigurinhaRecebida)
  end
  Attachment.prepend(ConversaCanal::FigurinhaNoAnexo) unless Attachment <= ConversaCanal::FigurinhaNoAnexo
end
