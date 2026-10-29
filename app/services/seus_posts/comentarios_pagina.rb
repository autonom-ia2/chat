# Seus posts F2 (#2305): os comentários de um post da Página da caixa, e responder como a Página, esconder, mostrar de
# novo e apagar. As mesmas chamadas do comentário do anúncio no Facebook (#2197: Meta::AdsGraphClient::PageComments e
# Crm::MetaAds::FacebookCommentRows), com o token da Página do próprio canal (Channel::FacebookPage), como o F1 já lê os
# números: não depende da conexão de Anúncios. O privado da Página é a F4 (pages_messaging).
#
# Quem chama (Api::V1::Accounts::SeusPostsComentariosController) já conferiu a flag, a chave, que a pessoa vê a caixa do
# Messenger da Página (a do próprio canal) e que o post é do perfil (SeusPosts::Leitura#post). Aqui, só comentário do
# post passa (Crm::MetaAds::FacebookCommentId: o id do comentário traz o do post); qualquer outro é
# `comment_not_found`, sem chamar a Meta. Ler pede pages_read_user_content; agir, pages_manage_engagement. Sem elas, ou
# com o token caído, `needs_permission` (o "Libere o acesso" do F1). A Meta diz em cada comentário o que o token pode
# (can_comment, can_hide, can_remove), e os botões seguem isso.
#
# Cada ação fica em crm_meta_ads_comment_actions, sem anúncio e sem o texto. Erros: `comment_not_found`,
# `invalid_text`, `needs_permission`, `meta_unavailable` e `meta_refused`.
class SeusPosts::ComentariosPagina
  Error = Crm::MetaAds::FacebookComments::Error

  NETWORK = Crm::MetaAds::FacebookComments::NETWORK

  def initialize(canal, can_manage:)
    @canal = canal
    @can_manage = can_manage
  end

  def payload(post_id, after: nil)
    return mais(post_id, after) if after

    result = client.post_comments(post_id)
    return vazio if permission_error?(result)

    comments = graph!(result)['comments'].to_h
    { status: 'ready', comments: rows(comments['data']), total: comments.dig('summary', 'total_count'), next_cursor: next_cursor(comments) }
  end

  def reply!(post_id, comment_id, message, user:)
    text = message.to_s.strip
    raise Error, 'invalid_text' if text.empty? || text.length > Crm::MetaAds::FacebookComments::MESSAGE_MAX

    { id: act!(post_id, comment_id, 'reply', user) { client.reply_comment(comment_id, text) }['id'] }
  end

  def hide!(post_id, comment_id, hidden:, user:)
    act!(post_id, comment_id, hidden ? 'hide' : 'show', user) { client.hide_comment(comment_id, hidden) }
    { id: comment_id, hidden: hidden }
  end

  # Irreversível: some do Facebook. A tela confirma antes.
  def delete!(post_id, comment_id, user:)
    act!(post_id, comment_id, 'delete', user) { client.delete_comment(comment_id) }
    { id: comment_id }
  end

  private

  def mais(post_id, after)
    result = client.more_post_comments(post_id, after.to_s)
    return vazio if permission_error?(result)

    data = graph!(result)
    { status: 'ready', comments: rows(data['data']), total: nil, next_cursor: next_cursor(data) }
  end

  def act!(post_id, comment_id, acao, user)
    raise Error, 'comment_not_found' unless Crm::MetaAds::FacebookCommentId.of_post?(comment_id.to_s, post_id.to_s)

    result = yield
    raise Error, 'needs_permission' if permission_error?(result)

    data = graph!(result)
    record_action(acao, comment_id, user)
    data
  end

  # A Meta já agiu quando isto roda: falha ao gravar vai ao rastreador e a resposta continua dizendo a verdade.
  def record_action(acao, comment_id, user)
    Crm::MetaAdsCommentAction.record!(account: @canal.account, network: NETWORK, ad_id: nil, comment_id: comment_id.to_s,
                                      action: acao, actor: 'user', user: user)
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: @canal.account).capture_exception
  end

  def rows(data)
    Crm::MetaAds::FacebookCommentRows.build(data, @canal.page_id.to_s, @can_manage)
  end

  def vazio
    { status: 'needs_permission', comments: [], total: 0, next_cursor: nil }
  end

  def permission_error?(result)
    !result.ok && (result.scope_error? || result.token_invalid?)
  end

  def graph!(result)
    return result.data.to_h if result.ok

    raise Error, result.transient? ? 'meta_unavailable' : 'meta_refused'
  end

  def next_cursor(edge)
    edge.dig('paging', 'cursors', 'after') if edge.dig('paging', 'next').present?
  end

  def client
    @client ||= Meta::AdsGraphClient.new(access_token: @canal.page_access_token).extend(Meta::AdsGraphClient::PageComments)
  end
end
