# Seus posts (#2302): os posts da Página da caixa (token da Página). Vezes que apareceu vêm com o recorte is_from_ads
# ("0" sem pagar, "1" de anúncio), numa chamada própria; o post com vezes de anúncio foi impulsionado e fica fora do
# normal. Pessoas, cliques, curtidas e comentários do post incluem o anúncio quando houve.
class SeusPosts::PostsPagina < SeusPosts::Posts
  COMPARAVEIS = %i[views reach likes comments clicks].freeze
  SEM_ANUNCIO = '0'.freeze
  DE_ANUNCIO = '1'.freeze

  private

  def ler_posts(janela)
    vistas = lista(api.seus_posts_page_views(page_id, janela)).to_h { |item| [item['id'], item['insights']] }
    lista(api.seus_posts_page(page_id, janela)).map { |item| post(item, vistas[item['id']]) }
  end

  def post(item, vistas)
    numeros = da_vida_toda(item['insights'])
    de_anuncio = lado(vistas, DE_ANUNCIO)
    # A Meta manda os dois lados de is_from_ads, até com 0 (chamada real de 27/10). Sem o lado de anúncio, não dá para
    # saber se o post teve anúncio: boosted nil (não se sabe), nunca false.
    impulsionado = de_anuncio.is_a?(Numeric) ? de_anuncio.positive? : nil
    {
      id: item['id'], text: item['message'].to_s, type: nil, image_url: item['full_picture'],
      permalink: item['permalink_url'], created_time: item['created_time'], boosted: impulsionado,
      views: lado(vistas, SEM_ANUNCIO), views_from_ads: de_anuncio, reach: numeros['post_total_media_view_unique'],
      clicks: numeros['post_clicks'], likes: item.dig('reactions', 'summary', 'total_count'),
      comments: item.dig('comments', 'summary', 'total_count'),
      # A Meta não manda `shares` no post que ninguém compartilhou (F2, #2305): sem o campo, 0.
      shares: item.dig('shares', 'count') || 0
    }
  end

  # Um lado do recorte is_from_ads da vida toda do post; sem o lado, sem número.
  def lado(insights, chave)
    metrica = Array(insights.to_h['data']).find { |item| item['name'] == 'post_media_view' && item['period'] == VIDA_TODA }
    Array(metrica&.dig('values')).find { |valor| valor['is_from_ads'] == chave }&.dig('value')
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
