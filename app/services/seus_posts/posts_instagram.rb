# Seus posts (#2302): os posts do Instagram da caixa (login do Instagram, graph.instagram.com). Só as vezes são sem
# anúncio; curtidas, comentários, pessoas, salvos e compartilhamentos podem incluir (#2522: a chamada real de 27/10 só
# viu posts nunca impulsionados, e a tela marca "pode incluir anúncio" até haver chamada real num post impulsionado,
# com o mesmo texto ao lado dos números). O login do Instagram não diz se o post foi impulsionado
# (sem boost_ads_list): boosted é nil ("não se sabe"), e nenhum sai da média. Só vezes, curtidas e comentários se
# comparam com o normal: pessoas, salvos e compartilhamentos de um post impulsionado sem a gente saber puxariam a média.
class SeusPosts::PostsInstagram < SeusPosts::Posts
  COMPARAVEIS = %i[views likes comments].freeze
  TIPOS = { 'IMAGE' => 'foto', 'VIDEO' => 'video', 'CAROUSEL_ALBUM' => 'carrossel' }.freeze

  private

  def ler_posts(janela)
    lista(api.seus_posts_instagram(janela)).map { |media| post(media) }
  end

  def post(media)
    numeros = da_vida_toda(media['insights'])
    {
      id: media['id'], text: media['caption'].to_s, type: TIPOS[media['media_type']],
      image_url: media['media_type'] == 'VIDEO' ? media['thumbnail_url'] : media['media_url'],
      permalink: media['permalink'], created_time: media['timestamp'], boosted: nil,
      views: numeros['views'], reach: numeros['reach'], likes: numeros['likes'], comments: numeros['comments'],
      saved: numeros['saved'], shares: numeros['shares']
    }
  end

  def token
    channel.access_token
  end

  def api
    @api ||= client(base_uri: channel.graph_host, instagram_node: channel.graph_node)
  end
end
