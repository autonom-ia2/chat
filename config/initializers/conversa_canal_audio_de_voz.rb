# frozen_string_literal: true

# #1702 — Nota de voz ou arquivo de áudio: a marca `voice` da Cloud API vira `meta.is_voice_message` e chega à tela.
# Prepends próprios; os arquivos do Chatwoot ficam intactos. Ver ConversaCanal::AudioDeVozRecebido.
Rails.application.config.to_prepare do
  unless Whatsapp::IncomingMessageBaseService <= ConversaCanal::AudioDeVozRecebido
    Whatsapp::IncomingMessageBaseService.prepend(ConversaCanal::AudioDeVozRecebido)
  end
  Attachment.prepend(ConversaCanal::AudioDeVozNoAnexo) unless Attachment <= ConversaCanal::AudioDeVozNoAnexo
end
