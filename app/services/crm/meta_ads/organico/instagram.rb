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
  # Tipos de conteúdo do recorte media_product_type conhecidos. Tipo novo fica indisponível: sem saber se é pago, não
  # entra nem sai do número.
  ORGANICOS = %w[POST REEL STORY CAROUSEL_CONTAINER].freeze
  POR_TIPO = %w[media_product_type].freeze
  POR_TIPO_E_SEGUIDOR = %w[media_product_type follow_type].freeze

  private

  def numeros
    @perfil = ler(api.instagram_profile)
    {
      status: 'ok', username: @perfil['username'], link: "https://www.instagram.com/#{@perfil['username']}",
      followers: @perfil['followers_count']&.to_i, **janela(periodo.atual), **comparacao, top_posts: top_posts
    }
  end

  def bloqueado
    { status: 'needs_permission', username: @perfil&.dig('username') }.compact
  end

  def compara?
    periodo.dias < HISTORY_DAYS
  end

  def janela(window)
    alcance = ler(api.instagram_insights(window.merge(metric: 'reach', metric_type: 'total_value', period: 'day',
                                                      breakdown: 'media_product_type,follow_type')))
    resto = ler(api.instagram_insights(window.merge(metric: 'views,total_interactions', metric_type: 'total_value', period: 'day',
                                                    breakdown: 'media_product_type')))
    follows = ler(api.instagram_insights(window.merge(metric: 'follows_and_unfollows', metric_type: 'total_value',
                                                      breakdown: 'follow_type', period: 'day')))
    {
      reach: sem_anuncio(alcance, 'reach', POR_TIPO_E_SEGUIDOR),
      reach_non_followers: sem_anuncio(alcance, 'reach', POR_TIPO_E_SEGUIDOR, follow_type: 'NON_FOLLOWER'),
      views: sem_anuncio(resto, 'views', POR_TIPO), interactions: sem_anuncio(resto, 'total_interactions', POR_TIPO),
      new_followers: total(follows, 'follows_and_unfollows', dimensao: 'FOLLOWER')
    }
  end

  # Soma dos lados orgânicos do recorte; com follow_type, só os desse lado. Lado sem valor fica fora; nenhum lado com
  # valor é "sem número" (nil), nunca 0. A métrica que veio 0 sem os lados (período parado) é 0. Ao contrário da
  # Página, o Instagram não manda o tipo zerado: na conta real (27/10) o período parado veio só com a linha AD. Por
  # isso tipo orgânico ausente, com outros lados com valor, é 0.
  def sem_anuncio(data, name, chaves, follow_type: nil)
    recorte = recorte_por_tipo(data, name, chaves)
    return 0 if recorte.empty?

    com_valor = Array(recorte['results']).select { |resultado| resultado['value'].is_a?(Numeric) }
    return if com_valor.empty?

    com_valor.sum { |resultado| conta?(recorte, resultado, name, follow_type) ? resultado['value'] : 0 }
  end

  def conta?(recorte, resultado, name, follow_type)
    lado = recorte['dimension_keys'].zip(Array(resultado['dimension_values'])).to_h
    organico?(lado['media_product_type'], name) && (follow_type.nil? || lado['follow_type'] == follow_type)
  end

  def organico?(tipo, name)
    return false if tipo == ANUNCIO
    return true if ORGANICOS.include?(tipo)

    indisponivel!("#{name}: tipo de conteúdo desconhecido #{tipo.inspect}")
  end

  # O recorte tem de trazer as dimensões pedidas e os lados (`results`, não vazio). Só a métrica que vem explicitamente
  # 0 pode vir sem os lados (formato real do período parado); zero sem o total vale quando vem nos lados. Fora disso, o
  # número com o pago não aparece: fica indisponível.
  def recorte_por_tipo(data, name, chaves)
    valor = metrica(data, name)&.dig('total_value') || indisponivel!("#{name} não veio")
    recorte = Array(valor['breakdowns']).first.to_h
    return {} if zerada_sem_lados?(valor, recorte)

    indisponivel!("#{name} sem o recorte #{chaves.join(',')}") unless (chaves - Array(recorte['dimension_keys'])).empty?
    indisponivel!("#{name} sem os lados do recorte") if Array(recorte['results']).empty?

    recorte
  end

  def zerada_sem_lados?(valor, recorte)
    valor['value'].is_a?(Numeric) && valor['value'].zero? && Array(recorte['results']).empty?
  end

  # Alcance por post (media insights) sem recorte: conferido com chamada real em 27/10/2026 em dois posts impulsionados
  # (anúncio ativo e pausado). O anúncio entrega por outra mídia (creative.effective_instagram_media_id, fora de
  # me/media), e o reach do post ficou ordens de grandeza abaixo do reach do anúncio: não soma o pago. Dark post não
  # está em me/media.
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
