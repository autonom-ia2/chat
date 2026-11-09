# Seus posts F2 (#2305): os comentários que esperam a conta em cada post dos últimos SeusPosts::Posts::HISTORICO_DIAS
# dias, numa chamada por página de posts, com os comentários embutidos (Meta::AdsGraphClient::SeusPosts). Sem uma
# chamada por post.
#
# Espera a conta o comentário de primeiro nível de outra pessoa, não escondido e sem resposta da conta. Aqui saem só os
# ids, lidos da Meta. Quem já recebeu o privado sai depois, em SeusPosts::Leitura, que lê o banco a cada vez. Post com
# mais comentários do que os COMENTARIOS_POR_POST lidos vem com `mais: true`: a conta é "pelo menos".
#
# No Instagram, a resposta da conta vem em dobro e às vezes sem `from`: Crm::MetaAds::InstagramCommentThreads diz
# qual é da conta (#2313). Sem a permissão de ler comentários, `needs_permission`, como no F1.
#
# Post do Instagram impulsionado por aqui (#2804): os comentários do anúncio ficam noutra mídia, uma por anúncio, e
# vêm à parte em `anuncios` ({ ad_id => { ids:, mais: } }), só com Anúncios da Meta e os comentários do Instagram no
# anúncio ligados (SeusPosts::Anuncios), e só os anúncios da conta de anúncios conectada agora: os que o atalho do post
# abre. Uma chamada por anúncio, até ANUNCIOS_POR_LEITURA, com a mídia já guardada (Crm::MetaAds::Creation::AdMedia,
# sem ler o anúncio na Meta); anúncio sem a mídia guardada ainda não conta. Quem não pode abrir Anúncios não recebe essa parte (SeusPosts::Leitura).
class SeusPosts::Esperando < Crm::MetaAds::Organico::Lugar
  include SeusPosts::Orcamento

  # Teto de mídias de anúncio lidas por leitura (os anúncios mais recentemente ativados primeiro): a leitura fica
  # guardada 15 minutos (SeusPosts::Leitura), e o teto segura o tempo dela.
  ANUNCIOS_POR_LEITURA = 10

  private

  def numeros
    posts = Array(ler(chamada).to_h['data'])
    @sem_leitura = Set.new
    anuncios = instagram? ? midias_dos_anuncios(posts.pluck('id').map(&:to_s)) : []
    @respostas_do_painel = respostas_do_painel(posts + anuncios.pluck(:midia)) if instagram?
    pendentes = posts.to_h { |post| [post['id'].to_s, pendentes_do_post(post['comments'].to_h)] }
    { status: 'ok', pendentes: incompletos(com_anuncios(pendentes, anuncios)) }
  end

  # Post com anúncio cuja mídia não foi lida nesta leitura (sem a mídia guardada, além do teto ou fora do ar): a conta é
  # "pelo menos" (`anuncios_mais`), nunca menor sem aviso.
  def incompletos(pendentes)
    pendentes.to_h do |post_id, pendente|
      [post_id, @sem_leitura.include?(post_id) ? pendente.merge(anuncios_mais: true) : pendente]
    end
  end

  # [{ post_id:, ad_id:, midia: }]: a mídia de cada anúncio do post, com os comentários. Mídia apagada ou sem leitura
  # fica fora; a mesma mídia do post já foi contada.
  def midias_dos_anuncios(post_ids)
    conta = SeusPosts::Anuncios.ligados?(channel.account) && SeusPosts::Anuncios.conta_de_anuncios(channel.account_id)
    return [] unless conta

    lidos, cortados = alvos(post_ids, conta).partition.with_index { |_, indice| indice < ANUNCIOS_POR_LEITURA }
    cortados.each { |(post_id, _, _)| @sem_leitura << post_id }
    lidos.filter_map { |(post_id, ad_id, media_id)| midia_do_anuncio(post_id, ad_id, media_id) }
  end

  # [[post_id, ad_id, media_id]]. Mídia que não guardamos, que já é um post da lista ou que outro anúncio já leva não é
  # lida (nem contada) de novo.
  def alvos(post_ids, conta)
    por_post = Crm::MetaAdsCreatedObject.ads_by_post(channel.account_id, 'instagram', post_ids, ad_account_id: conta)
    midias = Crm::MetaAds::Creation::AdMedia.of(channel.account_id, por_post.values.flatten)
    todos = por_post.flat_map { |post_id, ad_ids| ad_ids.map { |ad_id| [post_id, ad_id, midias[ad_id]] } }
    com_midia, sem_midia = todos.partition { |(_, _, media_id)| media_id.present? }
    sem_midia.each { |(post_id, _, _)| @sem_leitura << post_id }
    com_midia.reject { |(_, _, media_id)| post_ids.include?(media_id) }.uniq { |(_, _, media_id)| media_id }
  end

  # Falha numa mídia de anúncio não tira o "esperando você" dos posts: aquele anúncio só não conta nesta leitura.
  def midia_do_anuncio(post_id, ad_id, media_id)
    midia = ler_do_post(api.seus_posts_instagram_media_comments(media_id))
    { post_id: post_id, ad_id: ad_id, midia: midia } if midia
  rescue Crm::MetaAds::Organico::Indisponivel => e
    Rails.logger.warn("[SeusPosts] conta=#{channel.account_id} anuncio=#{ad_id} esperando=unavailable code=#{e.codigo}")
    @sem_leitura << post_id
    nil
  end

  def com_anuncios(pendentes, anuncios)
    anuncios.each_with_object(pendentes.dup) do |anuncio, todos|
      atual = todos[anuncio[:post_id]]
      next if atual.nil?

      do_anuncio = pendentes_do_post(anuncio[:midia]['comments'].to_h)
      todos[anuncio[:post_id]] = atual.merge(anuncios: atual[:anuncios].to_h.merge(anuncio[:ad_id] => do_anuncio))
    end
  end

  def bloqueado
    { status: 'needs_permission' }
  end

  def pendentes_do_post(edge)
    linhas = Array(edge['data'])
    { ids: instagram? ? pendentes_instagram(linhas) : pendentes_pagina(linhas), mais: edge.dig('paging', 'next').present? }
  end

  def pendentes_instagram(linhas)
    fios = Crm::MetaAds::InstagramCommentThreads.new(linhas, channel.instagram_id, own_ids: @respostas_do_painel)
    fios.top.filter_map do |comentario|
      next if fios.own?(comentario) || comentario['hidden'] == true || fios.replies(comentario).any? { |resposta| fios.own?(resposta) }

      comentario['id'].to_s
    end
  end

  # As respostas que a conta publicou pelo painel (`page_reply`), numa consulta só para todos os posts: a Graph as
  # devolve sem `from` (#2313).
  def respostas_do_painel(posts)
    ids = posts.flat_map do |post|
      Array(post.dig('comments', 'data')).flat_map { |item| Array(item.dig('replies', 'data')).pluck('id') }
    end
    Crm::MetaAdsCommentAction.where(account_id: channel.account_id, network: 'instagram', action: 'page_reply', comment_id: ids.map(&:to_s))
                             .pluck(:comment_id)
  end

  def pendentes_pagina(linhas)
    pagina = channel.page_id.to_s
    linhas.filter_map do |comentario|
      respostas = Array(comentario.dig('comments', 'data'))
      next if comentario.dig('from', 'id').to_s == pagina || comentario['is_hidden'] == true ||
              respostas.any? { |resposta| resposta.dig('from', 'id').to_s == pagina }

      comentario['id'].to_s
    end
  end

  def chamada
    return api.seus_posts_instagram_comments(historico) if instagram?

    api.seus_posts_page_comments(channel.page_id, historico)
  end

  def historico
    ate = periodo.atual[:until]
    { since: ate - SeusPosts::Posts::HISTORICO_DIAS.days.to_i, until: ate }
  end

  def instagram?
    channel.is_a?(Channel::Instagram)
  end

  def token
    instagram? ? channel.access_token : channel.page_access_token
  end

  def api
    @api ||= instagram? ? client(base_uri: channel.graph_host, instagram_node: channel.graph_node) : client
  end
end
