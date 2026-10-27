# Seus posts (#2199): a Página do Facebook da caixa, com o token da Página (read_insights). Métricas e formatos
# conferidos com chamada real na v23.0 (27/10/2026):
# - quem viu: page_total_media_view_unique com period=total_over_range, um valor só, cada pessoa uma vez no período;
# - vezes que apareceu: page_media_view por dia, com o recorte is_from_ads ("0" sem pagar, "1" de anúncio);
# - curtidas e comentários (page_post_engagements) e seguidores novos (page_daily_follows_unique), somados por dia.
class Crm::MetaAds::Organico::Pagina < Crm::MetaAds::Organico::Lugar
  private

  def numeros
    perfil = ler(api.page_profile(page_id))
    atual = janela(periodo.atual)
    {
      status: 'ok', name: perfil['name'], link: perfil['link'], followers: perfil['followers_count'].to_i,
      **atual, previous: janela(periodo.anterior).except(:views_from_ads), top_posts: top_posts
    }
  end

  def bloqueado
    { status: 'needs_permission', name: channel.inbox.name }
  end

  def janela(window)
    alcance = ler(api.page_insights(page_id, window.merge(metric: 'page_total_media_view_unique', period: 'total_over_range')))
    vistas = ler(api.page_insights(page_id, window.merge(metric: 'page_media_view', metric_type: 'total_value',
                                                         breakdown: 'is_from_ads', period: 'day')))
    resto = ler(api.page_insights(page_id, window.merge(metric: 'page_post_engagements,page_daily_follows_unique', period: 'day')))
    {
      reach: primeiro(alcance, 'page_total_media_view_unique'),
      views: soma(vistas, 'page_media_view'),
      views_from_ads: soma(vistas, 'page_media_view', is_from_ads: '1'),
      interactions: soma(resto, 'page_post_engagements'),
      new_followers: soma(resto, 'page_daily_follows_unique')
    }
  end

  def top_posts
    melhores(Array(ler(api.page_posts(page_id, periodo.atual))['data']).map { |post| post_da_pagina(post) })
  end

  def post_da_pagina(post)
    {
      id: post['id'], text: post['message'].to_s, image_url: post['full_picture'],
      reach: primeiro(post['insights'], 'post_total_media_view_unique'),
      interactions: post.dig('reactions', 'summary', 'total_count').to_i + post.dig('comments', 'summary', 'total_count').to_i +
        post.dig('shares', 'count').to_i,
      created_time: post['created_time'], permalink: post['permalink_url']
    }
  end

  def page_id
    channel.page_id
  end

  def token
    channel.page_access_token
  end

  def api
    @api ||= client
  end
end
