# frozen_string_literal: true

# #1702 — recebimento do WhatsApp oficial "igual ao app": apagada, editada, pedido, tipo da não suportada, encaminhada
# e áudio ouvido. Prepend próprio; os arquivos do Chatwoot ficam intactos. Ver ConversaCanal::RecebimentoDoWhatsapp.
Rails.application.config.to_prepare do
  unless Whatsapp::IncomingMessageBaseService <= ConversaCanal::RecebimentoDoWhatsapp
    Whatsapp::IncomingMessageBaseService.prepend(ConversaCanal::RecebimentoDoWhatsapp)
  end
end
