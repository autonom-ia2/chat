# IA cuida dos comentários (#2212): a resposta da pessoa ao privado volta para a conversa que nasceu do comentário,
# mesmo resolvida. Ela continua com o comentário no topo e com a escolha de quem continua.
#
# Na caixa sem "uma conversa por contato", o builder do Chatwoot abria conversa nova quando a última estava resolvida.
# Prepend no Messages::Instagram::BaseMessageBuilder e no Messages::Facebook::MessageBuilder; os builders ficam intactos
# (config/initializers/meta_ads_comentarios_ia.rb). Com a flag desligada, o builder segue como sempre (nem a consulta).
module Crm::MetaAds::ComentariosIa::VoltaAoComentario
  private

  def find_or_build_for_multiple_conversations
    return super unless @inbox&.account&.feature_enabled?(Crm::MetaAds::ComentariosIa::Cuidar::FLAG)

    Crm::MetaAds::ComentariosIa::Conversa.para_reabrir(Conversation.where(conversation_params)) || super
  end
end
