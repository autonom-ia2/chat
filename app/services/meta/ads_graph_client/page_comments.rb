# Comentários do post da Página por trás do anúncio (#2197). Entra no Meta::AdsGraphClient por `extend`, só nos clientes
# do Crm::MetaAds::FacebookComments: mesmas regras de token, versão e limpeza de erro. Sempre com o token da Página
# (pages_read_user_content para ler, pages_manage_engagement para responder, ocultar e apagar). Comentário de primeiro
# nível do mais novo para o mais antigo, com uma camada de respostas (o Facebook não aninha mais que isso), até
# REPLIES_LIMIT por comentário: anúncio raramente passa disso, e a casca não pagina respostas.
module Meta::AdsGraphClient::PageComments
  COMMENTS_PAGE_SIZE = 25
  REPLIES_LIMIT = 100
  COMMENT_FIELDS = 'id,from{id,name},message,attachment{type},created_time,is_hidden,can_hide,can_remove,can_comment'.freeze
  COMMENT_FIELDS_WITH_REPLIES = "#{COMMENT_FIELDS},comments.limit(#{REPLIES_LIMIT}){#{COMMENT_FIELDS}}".freeze
  POST_COMMENTS_FIELDS = 'permalink_url,comments.filter(toplevel).order(reverse_chronological)' \
                         ".limit(#{COMMENTS_PAGE_SIZE}).summary(total_count){#{COMMENT_FIELDS_WITH_REPLIES}}".freeze

  # Token e nome da Página, pedidos com o token da pessoa.
  def page_access(page_id)
    get(page_id.to_s, fields: 'access_token,name')
  end

  # Primeira página, com o link do post e o total, numa chamada só.
  def post_comments(post_id)
    get(post_id.to_s, fields: POST_COMMENTS_FIELDS)
  end

  def more_post_comments(post_id, after)
    get("#{post_id}/comments", fields: COMMENT_FIELDS_WITH_REPLIES, filter: 'toplevel', order: 'reverse_chronological',
                               limit: COMMENTS_PAGE_SIZE, after: after)
  end

  # O texto do post, para a IA que cuida dos comentários (#2424) saber do que o comentário fala.
  def page_post_message(post_id)
    get(post_id.to_s, fields: 'message')
  end

  # Um comentário, para o webhook `feed`, que chega só com os ids.
  def page_comment(comment_id)
    get(comment_id.to_s, fields: COMMENT_FIELDS)
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
