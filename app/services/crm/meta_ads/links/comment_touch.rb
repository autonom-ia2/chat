# Os toques de anúncio de uma conversa que nasceu do comentário de um anúncio (#2521), para o Links::Linker.
#
# A resposta no privado a um comentário de anúncio — da pessoa da equipe (#2196, #2197) ou da IA (#2212) — fica em
# Crm::MetaAdsCommentAction (`private_reply`, com o anúncio, a conversa da caixa e a hora). Conta como conversa do
# anúncio só o privado que a Meta aceitou e em que a pessoa escreveu de volta depois dele: é a mesma régua do clique
# para o WhatsApp, em que a conversa existe quando a pessoa manda a primeira mensagem. Comentário que não virou privado,
# ou privado sem resposta, fica fora; o número de comentários do anúncio é o da Meta (Panel::AdResults).
#
# O horário do toque é o da primeira mensagem da pessoa depois do privado; a chave é o comentário, para regravar nunca
# duplicar. O privado do Instagram entra na conversa que a pessoa já tinha aberta na caixa: aí o toque é a resposta ao
# privado, mas o card da conversa é o mesmo de antes e vai com ela para a coorte — a mesma regra do clique para o
# WhatsApp que cai numa conversa aberta.
module Crm::MetaAds::Links::CommentTouch
  KEY_PREFIX = 'meta_comment:'.freeze
  ORIGIN = 'comment'.freeze

  module_function

  # [{ touch_key:, ad_id:, touched_at: }], do mais antigo ao mais novo.
  def for(conversation)
    touches = private_replies(conversation).filter_map do |comment_id, ad_id, sent_at|
      replied_at = conversation.messages.incoming.where(created_at: sent_at..).minimum(:created_at)
      replied_at && { touch_key: "#{KEY_PREFIX}#{comment_id}", ad_id: ad_id, touched_at: replied_at }
    end
    touches.sort_by { |touch| touch[:touched_at] }
  end

  def private_replies(conversation)
    Crm::MetaAdsCommentAction.where(account_id: conversation.account_id, conversation_id: conversation.id, action: 'private_reply')
                             .where.not(ad_id: [nil, '']).where.not(confirmed_at: nil)
                             .pluck(:comment_id, :ad_id, :at)
  end
end
