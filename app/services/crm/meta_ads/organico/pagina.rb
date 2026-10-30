# Seus posts (#2199): a Página do Facebook da caixa, com o token da Página (read_insights). Métricas e formatos
# conferidos com chamada real na v23.0 (27/10/2026):
# - quem viu: page_total_media_view_unique com period=total_over_range, um valor só, cada pessoa uma vez no período;
# - vezes que apareceu: page_media_view por dia, com o recorte is_from_ads ("0" sem pagar, "1" de anúncio). `views` é só
#   o lado sem pagar; o de anúncio vai em `views_from_ads`, para a barra "vale pagar?";
# - quem viu e interações: page_total_media_view_unique e page_post_engagements aceitam is_from_ads mas ignoram o
#   recorte (chamada real de 27/10), então podem incluir o pago e a tela não os chama de "sem anúncio";
# - curtidas e comentários (page_post_engagements) e seguidores novos (page_daily_follows_unique), somados por dia.
class Crm::MetaAds::Organico::Pagina < Crm::MetaAds::Organico::Lugar
  private

  def numeros
    perfil = ler(api.page_profile(page_id))
    atual = janela(periodo.atual)
    {
      status: 'ok', name: perfil['name'], link: perfil['link'], followers: perfil['followers_count']&.to_i,
      **atual, **comparacao, top_posts: top_posts
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
      views: soma(com_recorte_de_anuncio(vistas), 'page_media_view', is_from_ads: '0'),
      views_from_ads: soma(vistas, 'page_media_view', is_from_ads: '1'),
      interactions: soma(resto, 'page_post_engagements'),
      new_followers: soma(resto, 'page_daily_follows_unique')
    }
  end

  # Sem a chave is_from_ads em nenhum dia, os dois lados virariam 0 em silêncio.
  def com_recorte_de_anuncio(vistas)
    dias = valores(vistas, 'page_media_view')
    indisponivel!('page_media_view sem o recorte is_from_ads') if dias.any? && dias.none? { |dia| dia.key?('is_from_ads') }
    vistas
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
