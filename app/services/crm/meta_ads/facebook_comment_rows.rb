# As linhas da aba Facebook dos comentários (#2197), na forma da casca comum (MetaAdsComments.vue, #2196), a partir do
# que a Graph devolve. `is_page`: o comentário é da própria Página. Os botões (`can_*`) só aparecem com
# pages_manage_engagement (`manage`) e quando a Meta deixa; a Página não responde a si mesma. Resposta no privado fica
# fora no Facebook (`can_reply_private` sempre false).
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
      replies: build(item.dig('comments', 'data'), page, manage)
    }
  end
end
