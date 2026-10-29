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
class SeusPosts::Esperando < Crm::MetaAds::Organico::Lugar
  include SeusPosts::Orcamento

  private

  def numeros
    posts = Array(ler(chamada).to_h['data'])
    @respostas_do_painel = respostas_do_painel(posts) if instagram?
    { status: 'ok', pendentes: posts.to_h { |post| [post['id'].to_s, pendentes_do_post(post['comments'].to_h)] } }
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
    @api ||= instagram? ? client(base_uri: Crm::MetaAds::Organico::INSTAGRAM_BASE_URI) : client
  end
end
