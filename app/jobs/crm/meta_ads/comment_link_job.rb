# Grava a ligação conversa → anúncio do privado de um comentário de anúncio (#2521), pelo Links::Linker, e avisa a tela
# aberta do painel. Enfileirado pelo Crm::MetaAdsCommentLinkListener na mensagem da pessoa.
class Crm::MetaAds::CommentLinkJob < ApplicationJob
  queue_as :low

  # A conversa tem privado de comentário de anúncio que a Meta aceitou e ainda não ligado a ele. Rodar de novo não
  # duplica (o Linker grava por upsert); isto só evita o trabalho a cada mensagem.
  def self.pending?(conversation)
    replies = Crm::MetaAds::Links::CommentTouch.private_replies(conversation).size
    replies.positive? &&
      Crm::MetaAdLink.where(conversation_id: conversation.id, origin: Crm::MetaAds::Links::CommentTouch::ORIGIN).count < replies
  end

  def perform(conversation_id)
    conversation = Conversation.find_by(id: conversation_id)
    return if conversation.blank?

    linked = Crm::MetaAds::Links::Linker.new(conversation).perform
    connection = Crm::MetaAdsConnection.active_for(conversation.account_id)
    Crm::MetaAds::Insights::Broadcaster.broadcast_throttled(connection) if linked.positive? && connection&.ad_account_id.present?
  end
end
