# frozen_string_literal: true

# #2212 — a resposta ao privado de um comentário volta para a conversa do comentário. Prepend no fork; os builders do
# Chatwoot ficam intactos.
Rails.application.config.to_prepare do
  [Messages::Instagram::BaseMessageBuilder, Messages::Facebook::MessageBuilder].each do |builder|
    builder.prepend(Crm::MetaAds::ComentariosIa::VoltaAoComentario) unless builder <= Crm::MetaAds::ComentariosIa::VoltaAoComentario
  end
end
