# Comentários do Facebook (#2197): o id de comentário da Graph é `<id do post>_<id do comentário>`, em que o id do post
# é a parte depois do `_` do id do post da Página (`<página>_<post>`); respostas idem (a confirmar na chamada real, até
# 07/11). Só comentário do post passa; qualquer outro formato não chega à Meta (Crm::MetaAds::FacebookComments).
module Crm::MetaAds::FacebookCommentId
  module_function

  def of_post?(comment_id, post_id)
    return false unless comment_id.is_a?(String) && post_id.is_a?(String)

    parts = comment_id.split('_', -1)
    parts.length == 2 && parts.all? { |part| digits?(part) } && parts.first == post_id.split('_').last
  end

  def digits?(text)
    text.present? && text.each_char.all? { |char| char.between?('0', '9') }
  end
end
