# Seus posts (#2199), parte do Meta::AdsGraphClient: o que os posts da Página e do Instagram alcançam, sem anúncio.
# Mesmas regras de token, versão e limpeza de erro (usa o `get`/`paged` privados dele).
# - Página: token da Página, com read_insights. graph.facebook.com.
# - Instagram: token do login do Instagram, com instagram_business_manage_insights. graph.instagram.com (base_uri).
module Meta::AdsGraphClient::Organico
  ORGANIC_PAGE_PROFILE_FIELDS = 'name,link,followers_count'.freeze
  ORGANIC_PAGE_POST_FIELDS = 'id,message,created_time,permalink_url,full_picture,shares,' \
                             'reactions.summary(total_count).limit(0),comments.summary(total_count).limit(0),' \
                             'insights.metric(post_total_media_view_unique)'.freeze
  ORGANIC_INSTAGRAM_PROFILE_FIELDS = 'username,followers_count'.freeze
  ORGANIC_INSTAGRAM_MEDIA_FIELDS = 'id,caption,timestamp,permalink,media_type,media_url,thumbnail_url,like_count,comments_count'.freeze
  # Teto de posts lidos por período (3 páginas de 100), para a leitura caber numa requisição da tela.
  ORGANIC_POSTS_MAX_PAGES = 3

  def page_profile(page_id)
    get(page_id.to_s, fields: ORGANIC_PAGE_PROFILE_FIELDS)
  end

  def page_insights(page_id, query)
    get("#{page_id}/insights", query)
  end

  # Posts publicados no período (since/until em segundos).
  def page_posts(page_id, window)
    organic_posts("#{page_id}/published_posts", window.merge(fields: ORGANIC_PAGE_POST_FIELDS))
  end

  def instagram_profile
    get('me', fields: ORGANIC_INSTAGRAM_PROFILE_FIELDS)
  end

  def instagram_insights(query)
    get('me/insights', query)
  end

  def instagram_media(window)
    organic_posts('me/media', window.merge(fields: ORGANIC_INSTAGRAM_MEDIA_FIELDS))
  end

  def instagram_media_reach(media_id)
    get("#{media_id}/insights", metric: 'reach')
  end

  private

  # Como o `paged`, com o teto de posts de Seus posts: { "data" => [...], "truncated" => bool } numa página só;
  # `truncated` diz que parou no teto com mais posts na Meta.
  # limit: posts por página; menor quando cada post traz os comentários embutidos (Seus posts, #2305).
  def organic_posts(path, query, limit: Meta::AdsGraphClient::LIST_LIMIT)
    rows = []
    result = each_page(path, query.merge(limit: limit), max_pages: ORGANIC_POSTS_MAX_PAGES) { |page| rows.concat(page) }
    return result unless result.ok

    Meta::AdsGraphClient::Result.new(ok: true, http_code: 200,
                                     data: { 'data' => rows, 'truncated' => result.data.to_h.dig('paging', 'next').present? })
  end
end
