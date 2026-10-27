# Seus posts (#2199): o Instagram da caixa, com o token do login do Instagram (instagram_business_manage_insights), em
# graph.instagram.com. Formatos conferidos com chamada real na v23.0 (27/10/2026): com metric_type=total_value a Meta
# devolve um total por métrica no período, inclusive em 90 dias; follows_and_unfollows e o recorte follow_type vêm em
# total_value.breakdowns. Com menos de 100 seguidores a Meta não manda follows_and_unfollows: seguidores novos nulos.
# Em 90 dias não há período anterior (a Meta guarda 90 dias do Instagram).
#
# Sem anúncio: o total da conta soma o que os anúncios alcançaram (media_product_type AD, inclusive dark post). Na conta
# real conferida em 27/10, o anúncio era quase todo o alcance, que passava das vezes que apareceu. Os números vêm do
# recorte por tipo de conteúdo, sem o AD. Vezes que apareceu e interações somam certo entre tipos; o alcance não (a Meta
# não deduplica: a mesma pessoa pode ter visto um post e um story), então é o teto e a tela diz "até N pessoas".
class Crm::MetaAds::Organico::Instagram < Crm::MetaAds::Organico::Lugar
  HISTORY_DAYS = 90
  ANUNCIO = 'AD'.freeze

  private

  def numeros
    @perfil = ler(api.instagram_profile)
    {
      status: 'ok', username: @perfil['username'], link: "https://www.instagram.com/#{@perfil['username']}",
      followers: @perfil['followers_count'].to_i, **janela(periodo.atual), **comparacao, top_posts: top_posts
    }
  end

  def bloqueado
    { status: 'needs_permission', username: @perfil&.dig('username') }.compact
  end

  def compara?
    periodo.dias < HISTORY_DAYS
  end

  def primeiro_post(window)
    api.instagram_first_post(window)
  end

  def janela(window)
    alcance = ler(api.instagram_insights(window.merge(metric: 'reach', metric_type: 'total_value', period: 'day',
                                                      breakdown: 'media_product_type,follow_type')))
    resto = ler(api.instagram_insights(window.merge(metric: 'views,total_interactions', metric_type: 'total_value', period: 'day',
                                                    breakdown: 'media_product_type')))
    follows = ler(api.instagram_insights(window.merge(metric: 'follows_and_unfollows', metric_type: 'total_value',
                                                      breakdown: 'follow_type', period: 'day')))
    {
      reach: sem_anuncio(alcance, 'reach'), reach_non_followers: sem_anuncio(alcance, 'reach', follow_type: 'NON_FOLLOWER'),
      views: sem_anuncio(resto, 'views'), interactions: sem_anuncio(resto, 'total_interactions'),
      new_followers: total(follows, 'follows_and_unfollows', dimensao: 'FOLLOWER')
    }
  end

  # Soma dos lados do recorte que não são anúncio; com follow_type, só os desse lado.
  def sem_anuncio(data, name, follow_type: nil)
    recorte = recorte_por_tipo(data, name)
    Array(recorte['results']).sum do |resultado|
      lado = Array(recorte['dimension_keys']).zip(Array(resultado['dimension_values'])).to_h
      next 0 if lado['media_product_type'] == ANUNCIO || (follow_type && lado['follow_type'] != follow_type)

      resultado['value'].to_i
    end
  end

  # Lado sem nada: a Meta não manda `results`. Número sem o recorte não dá para separar o anúncio, e a tela não mostra
  # o total com o pago.
  def recorte_por_tipo(data, name)
    valor = metrica(data, name)&.dig('total_value').to_h
    recorte = Array(valor['breakdowns']).first
    raise Crm::MetaAds::Organico::Indisponivel, "#{name} sem o recorte media_product_type" if recorte.nil? && valor['value'].to_i.positive?

    recorte.to_h
  end

  def top_posts
    posts = Array(ler(api.instagram_media(periodo.atual))['data']).map { |media| post_do_instagram(media) }
    melhores(posts).map do |post|
      dados = ler_do_post(api.instagram_media_reach(post[:id]))
      post.merge(reach: dados && primeiro(dados, 'reach'))
    end
  end

  def post_do_instagram(media)
    {
      id: media['id'], text: media['caption'].to_s,
      image_url: media['media_type'] == 'VIDEO' ? media['thumbnail_url'] : media['media_url'],
      reach: 0, interactions: media['like_count'].to_i + media['comments_count'].to_i,
      created_time: media['timestamp'], permalink: media['permalink']
    }
  end

  def token
    channel.access_token
  end

  def api
    @api ||= client(base_uri: Crm::MetaAds::Organico::INSTAGRAM_BASE_URI)
  end
end
