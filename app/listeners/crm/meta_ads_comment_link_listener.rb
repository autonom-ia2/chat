# Liga ao anúncio a conversa do privado de um comentário quando a pessoa responde (#2521, Links::CommentTouch). Só
# confere se a conversa tem privado de comentário de anúncio ainda sem ligação e enfileira; o resto é do Linker.
class Crm::MetaAdsCommentLinkListener < BaseListener
  def message_created(event)
    message, = extract_message_and_account(event)
    return unless message.incoming?
    return unless Crm::MetaAds::CommentLinkJob.pending?(message.conversation)

    Crm::MetaAds::CommentLinkJob.perform_later(message.conversation_id)
  end
end
