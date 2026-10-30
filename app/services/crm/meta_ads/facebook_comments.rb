# Comentários do post da Página por trás do anúncio, no Facebook (#2197): ler, responder como a Página, ocultar e
# apagar. Chama a Meta ao vivo; o comentário não é gravado (dado de terceiro), só a ação em
# crm_meta_ads_comment_actions (#2196), sem o texto.
#
# - Pela tela: só o post do anúncio da conta de anúncios da conexão (Crm::MetaAds::AdManagement#ad); anúncio de outra
#   conta é `ad_not_found`; post apagado ou que a Meta não acha mais é `no_post`. Pelo evento do webhook
#   (`meta_ads.comment_received`, que leva só ids): `comment`, só em post de Página da conta (Crm::MetaAdsPage, #2195).
# - Tudo com o token da Página, pedido com o token da pessoa. Ler exige `pages_read_user_content`; responder, ocultar e
#   apagar, `pages_manage_engagement`. Sem a primeira (ou no modo `partner`, em que o token é o da plataforma), a aba
#   pede para entrar de novo com o Facebook (`needs_login`); sem a segunda, lê e não age. Falha passageira da Meta ao
#   conferir permissão ou pedir o token da Página é `meta_unavailable`, não `needs_login`. Sem token da Página (a
#   Página não foi escolhida no login, ou a pessoa não a administra) é `needs_login`: entrando de novo, ela escolhe a
#   Página. Recusa com erro que entrar de novo não resolve (a Página sumiu, id inválido) é `meta_refused`.
# - Só age em comentário do post (Crm::MetaAds::FacebookCommentId). Qualquer outro formato é `comment_not_found`, sem
#   chamar a Meta.
# - Ao ler a primeira página de comentários, quem pode gerir (`can_manage`) guarda a Página em Crm::MetaAdsPage e, na
#   primeira vez, o app assina o campo `feed` dela (Crm::MetaAds::PageSubscription, #2200) para o webhook de comentário
#   novo (Crm::MetaAds::FacebookFeed). Quem só vê lê sem gravar nada, e a página seguinte (`more`) nunca grava (#2359).
# - Ler e agir pela tela pedem ver a caixa do Messenger da Página (#2359, decisão A): o Channel::FacebookPage da conta
#   com o mesmo page_id, e `inbox_access` (InboxPolicy#show? de quem abre) dizendo sim. Sem essa caixa na conta é
#   `no_inbox` para todos, inclusive o administrador; com ela e sem ser dela, `not_inbox_member`. Nos dois casos a
#   Página não é lida (nem token, nem comentários) e as permissões da pessoa nem são conferidas; só o anúncio foi
#   lido, para achar a Página. O evento do webhook (`comment`) não passa por aqui: não há pessoa.
# - Resposta no privado (Private Reply) fica fora: exige pages_messaging (decisão de 25/10 na #2197; é do #2212).
#
# Erros: `ad_not_found`, `comment_not_found`, `needs_login`, `invalid_text`, `no_inbox`, `not_inbox_member`,
# `meta_unavailable` (rede, 5xx, limite) e `meta_refused` (qualquer outra recusa da Meta).
class Crm::MetaAds::FacebookComments
  class Error < Crm::MetaAds::AdManagement::Error; end

  READ = 'pages_read_user_content'.freeze
  MANAGE = 'pages_manage_engagement'.freeze
  NETWORK = 'facebook'.freeze
  FEED = %w[feed].freeze
  # Limite de texto de comentário no Facebook.
  MESSAGE_MAX = 8000

  def initialize(connection, inbox_access:, can_manage: false)
    @connection = connection
    @inbox_access = inbox_access
    @can_manage = can_manage
  end

  def list(ad_id)
    return empty('needs_login') unless @connection.own_token?

    post_id = post_id_for(ad_id)
    return empty('no_post') if post_id.blank?

    refusal = reading_refusal(post_id)
    return empty(refusal) if refusal

    client = page_client(post_id, remember: @can_manage)
    return empty('needs_login') if client.nil?

    result = client.post_comments(post_id)
    return empty('no_post') if result.missing_object?

    data = graph!(result)
    comments = data['comments'].to_h
    {
      status: 'ready', permalink_url: data['permalink_url'], comments: rows(comments['data'], page_id(post_id)),
      total: comments.dig('summary', 'total_count'), next_cursor: next_cursor(comments)
    }
  end

  def more(ad_id, cursor)
    return empty('needs_login') unless @connection.own_token?

    post_id = post_id!(ad_id)
    refusal = reading_refusal(post_id)
    return empty(refusal) if refusal

    client = page_client(post_id)
    return empty('needs_login') if client.nil?

    data = graph!(client.more_post_comments(post_id, cursor.to_s))
    { status: 'ready', comments: rows(data['data'], page_id(post_id)), next_cursor: next_cursor(data) }
  end

  # Pela tela: quem age é a pessoa (`user`), no post do anúncio.
  def reply!(ad_id, comment_id, message, user: nil)
    reply_to(post_id!(ad_id), comment_id, message, by_user(ad_id, user))
  end

  def hide!(ad_id, comment_id, hidden, user: nil)
    hide_in(post_id!(ad_id), comment_id, hidden, by_user(ad_id, user))
  end

  def delete!(ad_id, comment_id, user: nil)
    act!(post_id!(ad_id), comment_id, 'delete', by_user(ad_id, user)) { |client| client.delete_comment(comment_id) }
    true
  end

  # Para quem consome `meta_ads.comment_received` (#2212), que leva só ids: o comentário como a Graph devolve
  # (`message`, `from`, `attachment`), lido com o token da Página. Só em post de Página da conta e com a leitura
  # concedida; nil quando não dá para ler (a recusa vai ao log, só com ids). A Página já é da conta: aqui ela não é
  # registrada de novo.
  def comment(post_id, comment_id)
    return unless granted?(READ) && own_page?(post_id)
    raise Error, 'comment_not_found' unless Crm::MetaAds::FacebookCommentId.of_post?(comment_id, post_id)

    client = page_client(post_id)
    client && graph!(client.page_comment(comment_id))
  rescue Error => e
    raise if e.code == 'meta_unavailable'

    Rails.logger.warn("[meta_ads] comentário do Facebook não lido: #{e.code} account=#{@connection.account_id} comment=#{comment_id}")
    nil
  end

  # Pelo post, e não pelo anúncio: a tela (reply!/hide!) e a IA que cuida dos comentários (#2212), que age no comentário
  # que chegou pelo evento, sem pessoa. As mesmas regras: comentário do post, caixa do Messenger da Página na conta e
  # pages_manage_engagement. `by`: { actor:, user:, ad_id: }, gravado na ação.
  def reply_to(post_id, comment_id, message, by)
    text = message.to_s.strip
    raise Error, 'invalid_text' if text.empty? || text.length > MESSAGE_MAX

    { id: act!(post_id, comment_id, 'reply', by) { |client| client.reply_comment(comment_id, text) }['id'] }
  end

  def hide_in(post_id, comment_id, hidden, by)
    act!(post_id, comment_id, hidden ? 'hide' : 'show', by) { |client| client.hide_comment(comment_id, hidden) }
    hidden
  end

  private

  def by_user(ad_id, user)
    { actor: 'user', user: user, ad_id: ad_id }
  end

  def empty(status)
    { status: status, comments: [], total: 0, next_cursor: nil }
  end

  def user_client
    @user_client ||= graph_client(@connection.read_token)
  end

  # Só este serviço usa as chamadas de comentário: cada cliente ganha Meta::AdsGraphClient::PageComments para si, sem
  # crescer a classe comum.
  def graph_client(token)
    Meta::AdsGraphClient.new(access_token: token).extend(Meta::AdsGraphClient::PageComments)
  end

  def granted?(permission)
    @connection.own_token? && granted_permissions.include?(permission)
  end

  def granted_permissions
    @granted_permissions ||= begin
      result = user_client.permissions
      raise Error, 'meta_unavailable' if result.transient?

      entries = result.ok ? Array(result.data.to_h['data']) : []
      entries.filter_map { |entry| entry['permission'] if entry.is_a?(Hash) && entry['status'] == Meta::AdsGraphClient::GRANTED }
    end
  end

  def management
    @management ||= Crm::MetaAds::AdManagement.new(@connection)
  end

  def post_id_for(ad_id)
    ad = management.ad(ad_id)
    raise Error, 'ad_not_found' if ad.nil?

    ad.dig('creative', 'effective_object_story_id')
  rescue Crm::MetaAds::AdManagement::Error => e
    raise Error, e.code
  end

  def post_id!(ad_id)
    post_id_for(ad_id).presence || raise(Error, 'ad_not_found')
  end

  def page_id(post_id)
    post_id.to_s.split('_').first
  end

  def page_client(post_id, remember: false)
    @page_clients ||= {}
    page = page_id(post_id)
    return @page_clients[page] if @page_clients.key?(page)

    result = user_client.page_access(page)
    raise Error, 'meta_unavailable' if result.transient?

    data = result.ok ? result.data.to_h : page_refused!(result)
    token = data['access_token'].presence
    @page_clients[page] = token && (remember ? remember_page(page, data) : graph_client(token))
  end

  # Token ou permissão que faltam se resolvem entrando de novo (`needs_login`, pelo `{}`). O resto (a Página sumiu, id
  # inválido) não: entrar de novo daria a mesma recusa.
  def page_refused!(result)
    return {} if result.token_invalid? || result.scope_error?

    raise Error, 'meta_refused'
  end

  # A Página entra no resolvedor do webhook e, na primeira vez nesta conta, o `feed` dela é assinado (a assinatura une
  # os campos: não apaga o leadgen do #2195). Falha aqui não tira a lista da tela.
  def remember_page(page, data)
    client = graph_client(data['access_token'])
    Crm::MetaAdsPage.remember!(@connection.account, [{ 'id' => page, 'name' => data['name'] }])
    subscribe_feed(page, data['access_token'])
    client
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: @connection.account).capture_exception
    client
  end

  def subscribe_feed(page, token)
    record = Crm::MetaAdsPage.find_by(account_id: @connection.account_id, page_id: page)
    return if record.nil? || record.feed_receiving

    Crm::MetaAds::PageSubscription.new(page_id: page, access_token: token).add!(FEED)
    record.update!(feed_receiving: true)
  end

  # `by`: { actor:, user:, ad_id: }. O post já veio do anúncio da conta (post_id!).
  def act!(post_id, comment_id, acao, by)
    raise Error, 'comment_not_found' unless Crm::MetaAds::FacebookCommentId.of_post?(comment_id, post_id)

    refusal = inbox_refusal(post_id)
    raise Error, refusal if refusal
    raise Error, 'needs_login' unless granted?(MANAGE)

    client = page_client(post_id) || raise(Error, 'needs_login')
    data = graph!(yield(client))
    record_action(acao, comment_id, by)
    data
  end

  # A caixa vem antes da permissão de leitura: sem ela, o motivo é a caixa para todos, e entrar de novo não resolveria.
  def reading_refusal(post_id)
    inbox_refusal(post_id) || ('needs_login' unless granted?(READ))
  end

  # A caixa do Messenger da Página nesta conta, a mesma do webhook (Crm::MetaAds::FacebookFeed#inbox_id).
  def inbox_refusal(post_id)
    inbox = Channel::FacebookPage.find_by(account_id: @connection.account_id, page_id: page_id(post_id))&.inbox
    return 'no_inbox' if inbox.nil?

    'not_inbox_member' unless @inbox_access.call(inbox)
  end

  def own_page?(post_id)
    Crm::MetaAdsPage.account_ids_for(page_id(post_id)).include?(@connection.account_id)
  end

  # A Meta já agiu quando isto roda: falha ao gravar vai ao rastreador e a resposta continua dizendo a verdade.
  def record_action(acao, comment_id, by)
    Crm::MetaAdsCommentAction.record!(account: @connection.account, network: NETWORK, ad_id: by[:ad_id], comment_id: comment_id,
                                      action: acao, actor: by[:actor], user: by[:user])
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: @connection.account).capture_exception
  end

  def graph!(result)
    return result.data.to_h if result.ok

    raise Error, result.transient? ? 'meta_unavailable' : 'meta_refused'
  end

  def next_cursor(edge)
    edge.dig('paging', 'cursors', 'after') if edge.dig('paging', 'next').present?
  end

  def rows(data, page)
    Crm::MetaAds::FacebookCommentRows.build(data, page, granted?(MANAGE))
  end
end
