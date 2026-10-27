# Comentários do post da Página por trás do anúncio (#2197), parte do Meta::AdsGraphClient: mesmas regras de token,
# versão e limpeza de erro. Sempre com o token da Página (pages_read_user_content para ler, pages_manage_engagement
# para responder, ocultar e apagar). Comentário de primeiro nível do mais novo para o mais antigo, com uma camada de
# respostas (o Facebook não aninha mais que isso).
module Meta::AdsGraphClient::PageComments
  COMMENTS_PAGE_SIZE = 25
  COMMENT_FIELDS = 'id,from{id,name},message,created_time,is_hidden,can_hide,can_remove,can_comment'.freeze
  COMMENT_FIELDS_WITH_REPLIES = "#{COMMENT_FIELDS},comments.limit(#{COMMENTS_PAGE_SIZE}){#{COMMENT_FIELDS}}".freeze
  POST_COMMENTS_FIELDS = 'permalink_url,comments.filter(toplevel).order(reverse_chronological)' \
                         ".limit(#{COMMENTS_PAGE_SIZE}).summary(total_count){#{COMMENT_FIELDS_WITH_REPLIES}}".freeze

  # Primeira página, com o link do post e o total, numa chamada só.
  def post_comments(post_id)
    get(post_id.to_s, fields: POST_COMMENTS_FIELDS)
  end

  def more_post_comments(post_id, after)
    get("#{post_id}/comments", fields: COMMENT_FIELDS_WITH_REPLIES, filter: 'toplevel', order: 'reverse_chronological',
                               limit: COMMENTS_PAGE_SIZE, after: after)
  end

  # Sai como a Página, embaixo do comentário.
  def reply_comment(comment_id, message)
    post("#{comment_id}/comments", message: message)
  end

  def hide_comment(comment_id, hidden)
    post(comment_id.to_s, is_hidden: hidden)
  end

  def delete_comment(comment_id)
    request(:delete, comment_id.to_s)
  end
end
