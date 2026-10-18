# frozen_string_literal: true

# #1702 — PDF com a prévia da 1ª página no cartão, como no app. Prepend próprio; os arquivos do Chatwoot ficam
# intactos. O gerador de prévia (Poppler) só aceita PDF de conta com a pele (ConversaCanal::PreviaDoPdfDaPele).
# O to_prepare roda antes do after_initialize em que o Active Storage copia `config.active_storage.previewers`
# (vazio no Chatwoot); a 2ª linha refaz a troca a cada recarga de código.
Rails.application.config.to_prepare do
  Rails.application.config.active_storage.previewers = [ConversaCanal::PreviaDoPdfDaPele]
  ActiveStorage.previewers = [ConversaCanal::PreviaDoPdfDaPele]
  Attachment.prepend(ConversaCanal::PreviaDoPdfNoAnexo) unless Attachment <= ConversaCanal::PreviaDoPdfNoAnexo
  ActiveStorage::Preview.prepend(ConversaCanal::PreviaDoPdfQueFalhou) unless ActiveStorage::Preview <= ConversaCanal::PreviaDoPdfQueFalhou
end
