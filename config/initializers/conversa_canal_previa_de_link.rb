# frozen_string_literal: true

# #1702 — Prévia de link igual ao WhatsApp: o texto com endereço sai com `preview_url` na Cloud API e o painel
# mostra o cartão (título, descrição, site, imagem) lido pelo servidor. Tudo no fork; os arquivos do Chatwoot
# ficam intactos. Ver ConversaCanal::PreviaDeLink.
Rails.application.config.to_prepare do
  unless Whatsapp::Providers::WhatsappCloudService <= ConversaCanal::PreviaDeLinkNoEnvio
    Whatsapp::Providers::WhatsappCloudService.prepend(ConversaCanal::PreviaDeLinkNoEnvio)
  end

  # A cópia da imagem da prévia fica presa à mensagem e sai com ela.
  Message.has_one_attached ConversaCanal::ImagemDaPrevia::ANEXO unless Message.reflect_on_attachment(ConversaCanal::ImagemDaPrevia::ANEXO)

  if Message._commit_callbacks.none? { |callback| callback.filter == ConversaCanal::PreviaDeLinkNaMensagem }
    Message.after_commit ConversaCanal::PreviaDeLinkNaMensagem, on: :create
  end
end
