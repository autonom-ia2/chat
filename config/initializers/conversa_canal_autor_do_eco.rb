# frozen_string_literal: true

# #1941 — eco do celular grava quem estava atribuído quando a mensagem chegou. Prepend próprio; os arquivos do
# Chatwoot ficam intactos. Ver ConversaCanal::AutorDoEco.
Rails.application.config.to_prepare do
  Whatsapp::IncomingMessageBaseService.prepend(ConversaCanal::AutorDoEco) unless Whatsapp::IncomingMessageBaseService <= ConversaCanal::AutorDoEco
end
