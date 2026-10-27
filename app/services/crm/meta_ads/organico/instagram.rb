# Seus posts (#2199): o Instagram da caixa, com o token do login do Instagram (instagram_business_manage_insights), em
# graph.instagram.com. Formatos conferidos com chamada real na v23.0 (27/10/2026): com metric_type=total_value a Meta
# devolve um total por métrica no período, inclusive em 90 dias; follows_and_unfollows e o recorte follow_type vêm em
# total_value.breakdowns. Com menos de 100 seguidores a Meta não manda follows_and_unfollows: seguidores novos nulos.
# Em 90 dias não há período anterior (a Meta guarda 90 dias do Instagram).
class Crm::MetaAds::Organico::Instagram < Crm::MetaAds::Organico::Lugar
  HISTORY_DAYS = 90

  private

  def numeros
    @perfil = ler(api.instagram_profile)
    atual = janela(periodo.atual)
    {
      status: 'ok', username: @perfil['username'], link: "https://www.instagram.com/#{@perfil['username']}",
      followers: @perfil['followers_count'].to_i, **atual, reach_non_followers: quem_nao_segue,
      previous: periodo.dias < HISTORY_DAYS ? janela(periodo.anterior) : nil, top_posts: top_posts
    }
  end

  def bloqueado
    { status: 'needs_permission', username: @perfil&.dig('username') }.compact
  end

  def janela(window)
    dados = ler(api.instagram_insights(window.merge(metric: 'reach,views,total_interactions', metric_type: 'total_value', period: 'day')))
    follows = ler(api.instagram_insights(window.merge(metric: 'follows_and_unfollows', metric_type: 'total_value',
                                                      breakdown: 'follow_type', period: 'day')))
    {
      reach: total(dados, 'reach').to_i, views: total(dados, 'views').to_i,
      interactions: total(dados, 'total_interactions').to_i,
      new_followers: total(follows, 'follows_and_unfollows', dimensao: 'FOLLOWER')
    }
  end

  def quem_nao_segue
    data = ler(api.instagram_insights(periodo.atual.merge(metric: 'reach', metric_type: 'total_value', breakdown: 'follow_type',
                                                          period: 'day')))
    total(data, 'reach', dimensao: 'NON_FOLLOWER')
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
