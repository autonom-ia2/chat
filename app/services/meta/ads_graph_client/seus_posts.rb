# Seus posts (#2302, F1 #2304), parte do Meta::AdsGraphClient: os posts com os números de cada um, numa chamada por
# página de posts (chamada real de 27/10, v23). Mesmas regras de token, versão e limpeza de erro do cliente.
# - Página: token da Página. O recorte is_from_ads vai numa chamada própria: duas métricas com o mesmo recorte na mesma
#   chamada dão erro (code 2). post_total_media_view_unique vem duas vezes (lifetime e day): quem lê usa a lifetime.
# - Instagram: token do login do Instagram, graph.instagram.com (base_uri). Números lifetime de cada mídia.
# - Comentários dos posts, para "esperando você" (F2, #2305): os primeiros COMENTARIOS_POR_POST de primeiro nível de
#   cada post, com quem escreveu e quem respondeu, embutidos na lista de posts (chamada real de 29/10: veio nas duas
#   redes). Numa chamada própria: sem a permissão de ler comentários, só ela falha, e os números do F1 continuam.
#   POSTS_COM_COMENTARIOS por página, não 100: cada post traz até 50 comentários, e a resposta cresce. As respostas
#   de cada comentário vêm só na primeira página delas (25): resposta da conta depois disso não é vista, e o
#   comentário conta como esperando.
module Meta::AdsGraphClient::SeusPosts
  SEUS_POSTS_PAGE_FIELDS = 'id,message,created_time,permalink_url,full_picture,status_type,' \
                           'reactions.summary(total_count).limit(0),comments.summary(total_count).limit(0),' \
                           'insights.metric(post_total_media_view_unique,post_clicks)'.freeze
  SEUS_POSTS_PAGE_VIEWS_FIELDS = 'id,insights.metric(post_media_view).breakdown(is_from_ads).metric_type(total_value)'.freeze
  SEUS_POSTS_INSTAGRAM_FIELDS = 'id,caption,timestamp,permalink,media_type,media_url,thumbnail_url,' \
                                'insights.metric(views,reach,saved,shares,comments,likes)'.freeze
  COMENTARIOS_POR_POST = 50
  POSTS_COM_COMENTARIOS = 50
  SEUS_POSTS_INSTAGRAM_COMMENTS_FIELDS = "id,comments.limit(#{COMENTARIOS_POR_POST}){id,hidden,from{id},replies{id,from{id}}}".freeze
  SEUS_POSTS_PAGE_COMMENTS_FIELDS = "id,comments.filter(toplevel).limit(#{COMENTARIOS_POR_POST})" \
                                    '{id,is_hidden,from{id},comments.limit(25){id,from{id}}}'.freeze

  def seus_posts_page(page_id, window)
    organic_posts("#{page_id}/published_posts", window.merge(fields: SEUS_POSTS_PAGE_FIELDS))
  end

  def seus_posts_page_views(page_id, window)
    organic_posts("#{page_id}/published_posts", window.merge(fields: SEUS_POSTS_PAGE_VIEWS_FIELDS))
  end

  def seus_posts_instagram(window)
    organic_posts('me/media', window.merge(fields: SEUS_POSTS_INSTAGRAM_FIELDS))
  end

  def seus_posts_instagram_comments(window)
    organic_posts('me/media', window.merge(fields: SEUS_POSTS_INSTAGRAM_COMMENTS_FIELDS), limit: POSTS_COM_COMENTARIOS)
  end

  def seus_posts_page_comments(page_id, window)
    organic_posts("#{page_id}/published_posts", window.merge(fields: SEUS_POSTS_PAGE_COMMENTS_FIELDS), limit: POSTS_COM_COMENTARIOS)
  end
end
