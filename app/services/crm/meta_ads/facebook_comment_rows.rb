# As linhas da aba Facebook dos comentários (#2197), na forma da casca comum (MetaAdsComments.vue, #2196), a partir do
# que a Graph devolve. `is_page`: o comentário é da própria Página. Os botões (`can_*`) só aparecem com
# pages_manage_engagement (`manage`) e quando a Meta deixa; a Página não responde a si mesma. Resposta no privado fica
# fora no Facebook (`can_reply_private` sempre false). `attachment`: o tipo do anexo (photo, sticker…), para o
# comentário só com foto não aparecer vazio.
#
# PROVISÓRIO (#2197, até a chamada real de 07/11): as respostas vêm sem botões. O servidor só age em id de comentário
# no formato `<post>_<comentário>`, e o formato do id de uma resposta ainda não foi visto em dado real.
module Crm::MetaAds::FacebookCommentRows
  module_function

  def build(data, page, manage)
    Array(data).filter_map { |item| row(item, page, manage) if item.is_a?(Hash) }
  end

  def row(item, page, manage)
    own = item.dig('from', 'id').to_s == page
    {
      id: item['id'], author: { name: item.dig('from', 'name'), is_page: own }, text: item['message'],
      created_time: item['created_time'], hidden: item['is_hidden'] == true,
      can_reply: manage && !own && item['can_comment'] == true, can_hide: manage && item['can_hide'] == true,
      can_delete: manage && item['can_remove'] == true, can_reply_private: false,
      attachment: item.dig('attachment', 'type'), replies: build(item.dig('comments', 'data'), page, false)
    }
  end
end
