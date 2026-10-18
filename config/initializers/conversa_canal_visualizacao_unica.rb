# frozen_string_literal: true

# #1702 — Visualização única do WhatsApp: a mídia fica guardada e visível, com a marca `meta.is_view_once` no anexo.
# Prepend próprio; os arquivos do Chatwoot ficam intactos. Ver ConversaCanal::VisualizacaoUnica.
Rails.application.config.to_prepare do
  Attachment.prepend(ConversaCanal::VisualizacaoUnicaNoAnexo) unless Attachment <= ConversaCanal::VisualizacaoUnicaNoAnexo
end
