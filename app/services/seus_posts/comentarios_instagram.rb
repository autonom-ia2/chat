# Seus posts F2 (#2305): os comentários de um post do Instagram da caixa, e responder, mandar no privado, esconder,
# mostrar de novo e apagar. As mesmas chamadas do comentário do anúncio (#2196: Instagram::CommentsClient,
# Crm::MetaAds::InstagramPrivateReply e Crm::MetaAds::InstagramCommentRows), com o post do perfil no lugar do anúncio.
# Nada do comentário é gravado: é dado de terceiro, lido ao vivo.
#
# Quem chama (Api::V1::Accounts::SeusPostsComentariosController) já conferiu a flag, a chave, que a pessoa vê a caixa
# e que o post é do perfil (SeusPosts::Leitura#post). Aqui, cada ação confere na Meta que o comentário é desse post
# (`media`); de outro post, `comment_not_found`, sem agir.
#
# Erros (Error#code): `comment_not_found`, `invalid_text`, `needs_permission` (sem
# instagram_business_manage_comments, ou o token caiu: a tela mostra o "Libere o acesso" do F1), `meta_unavailable`,
# `meta_refused`, `private_reply_not_pending` e os do privado (Crm::MetaAds::InstagramPrivateReply).
class SeusPosts::ComentariosInstagram
  Error = Crm::MetaAds::InstagramPrivateReply::Error

  MAX_TEXT = Crm::MetaAds::InstagramComments::MAX_TEXT
  NETWORK = 'instagram'.freeze

  # conversation_access: se a pessoa enxerga a conversa do privado ("Ver conversa" só para ela).
  def initialize(canal, can_manage:, conversation_access:)
    @canal = canal
    @rows = Crm::MetaAds::InstagramCommentRows.new(canal, account_id: canal.account_id, can_manage: can_manage,
                                                          conversation_access: conversation_access)
  end

  def payload(post_id, after: nil)
    result = client.comments(post_id, after: after)
    return vazio if permission_error?(result)
    raise Error, failure(result) unless result.ok

    threads = Crm::MetaAds::InstagramCommentThreads.build(Array(result.data['data']), @canal, @canal.account_id)
    { status: 'ready', comments: @rows.present(threads), total: total(post_id, threads), next_cursor: next_cursor(result.data) }
  end

  # A resposta fica num nível só, como no app: responder a uma resposta vai para o comentário de cima. O id da resposta
  # fica gravado (`page_reply`): a Graph a devolve sem `from`, e é ele que a mostra como da conta (#2313).
  def reply!(post_id, comment_id, text, user:)
    text = valid_text!(text, MAX_TEXT)
    comment = comment_of!(post_id, comment_id)
    result = client.reply(comment['parent_id'].presence || comment_id, text)
    raise Error, failure(result) unless result.ok

    Crm::MetaAdsCommentAction.record_reply(account: @canal.account, ad_id: nil, reply_id: result.data['id'], user: user)
    @rows.row({ 'id' => result.data['id'].to_s, 'text' => text, 'timestamp' => Time.current.iso8601,
                'from' => { 'id' => @canal.instagram_id, 'username' => @canal.provider_name } }, actions: {}, own: true)
  end

  def hide!(post_id, comment_id, hidden:, user:)
    comment_of!(post_id, comment_id)
    result = client.hide(comment_id, hidden: hidden)
    raise Error, failure(result) unless result.ok

    record_action(hidden ? 'hide' : 'show', comment_id, user)
    { id: comment_id, hidden: hidden }
  end

  # Irreversível: some do Instagram. A tela confirma antes.
  def delete!(post_id, comment_id, user:)
    comment_of!(post_id, comment_id)
    result = client.delete(comment_id)
    raise Error, failure(result) unless result.ok

    record_action('delete', comment_id, user)
    { id: comment_id }
  end

  def private_reply!(post_id, comment_id, text, user:)
    valid_text!(text, Crm::MetaAds::InstagramPrivateReply::MAX_TEXT)
    comment = comment_of!(post_id, comment_id)
    sent = Crm::MetaAds::InstagramPrivateReply.new(@canal).perform!(comment: comment, text: text, actor: 'user', user: user)
    { sent_at: Time.current.iso8601, conversation_path: @rows.conversation_path(sent[:conversation]) }
  rescue Error => e
    # O privado chama a falta de permissão de `needs_login`, o nome da aba de Anúncios; aqui é o "Libere o acesso".
    raise Error, e.code == 'needs_login' ? 'needs_permission' : e.code
  end

  # "Não foi enviado": a pessoa conferiu no Direct que o privado sem confirmação não chegou e libera o botão. Só a linha
  # sem confirmação desse comentário, nesta conta, fora de anúncio, e nunca com o envio em andamento
  # (Crm::MetaAdsCommentAction#releasable?).
  def release_private_reply!(post_id, comment_id)
    comment_of!(post_id, comment_id)
    action = Crm::MetaAdsCommentAction.find_by(account_id: @canal.account_id, network: NETWORK, action: 'private_reply',
                                               comment_id: comment_id.to_s, ad_id: nil, confirmed_at: nil)
    raise Error, 'private_reply_not_pending' if action.nil? || !action.releasable?

    action.destroy!
    { id: comment_id.to_s }
  end

  private

  def comment_of!(post_id, comment_id)
    result = client.comment(comment_id)
    raise Error, 'needs_permission' if permission_error?(result)
    raise Error, 'comment_not_found' if !result.ok || result.data.dig('media', 'id').to_s != post_id.to_s

    result.data
  end

  # A Meta já agiu quando isto roda: falha ao gravar vai ao rastreador e a resposta continua dizendo a verdade.
  def record_action(acao, comment_id, user)
    Crm::MetaAdsCommentAction.record!(account: @canal.account, network: NETWORK, ad_id: nil, comment_id: comment_id.to_s,
                                      action: acao, actor: 'user', user: user)
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: @canal.account).capture_exception
  end

  def vazio
    { status: 'needs_permission', comments: [], total: 0, next_cursor: nil }
  end

  # Total de comentários do post como a Meta conta; sem ele, o que veio nesta página, sem a cópia em dobro.
  def total(post_id, threads)
    result = client.comments_count(post_id)
    return result.data['comments_count'].to_i if result.ok && result.data.key?('comments_count')

    threads.ids.size
  end

  def next_cursor(data)
    data.dig('paging', 'cursors', 'after') if data.dig('paging', 'next').present?
  end

  def valid_text!(text, limit)
    text = text.to_s.strip
    raise Error, 'invalid_text' if text.blank? || text.length > limit

    text
  end

  def permission_error?(result)
    !result.ok && (result.scope_error? || result.token_invalid?)
  end

  def failure(result)
    return 'needs_permission' if permission_error?(result)

    result.transient? ? 'meta_unavailable' : 'meta_refused'
  end

  def client
    @client ||= Instagram::CommentsClient.new(@canal)
  end
end
