# Comentários do post da Página por trás do anúncio, no Facebook (#2197): ler, responder como a Página, ocultar e
# apagar. Chama a Meta ao vivo; o comentário não é gravado (dado de terceiro), só a ação em
# crm_meta_ads_comment_actions (#2196), sem o texto.
#
# - Pela tela: só o post do anúncio da conta de anúncios da conexão (Crm::MetaAds::AdManagement#ad); anúncio de outra
#   conta é `ad_not_found`. Pela IA (#2212): `*_on_post!`, só em post de Página da conta (Crm::MetaAdsPage, #2195).
# - Tudo com o token da Página, pedido com o token da pessoa. Ler exige `pages_read_user_content`; responder, ocultar e
#   apagar, `pages_manage_engagement`. Sem a primeira (ou no modo `partner`, em que o token é o da plataforma), a aba
#   pede para entrar de novo com o Facebook (`needs_login`); sem a segunda, lê e não age. Falha passageira da Meta ao
#   conferir permissão ou pedir o token da Página é `meta_unavailable`, não `needs_login`.
# - Só age em comentário do post. O id de comentário da Graph é `<id do post>_<id do comentário>`, em que o id do post
#   é a parte depois do `_` do id do post da Página (`<página>_<post>`); respostas idem (a confirmar na chamada real,
#   até 07/11). Qualquer outro formato é `comment_not_found`, sem chamar a Meta.
# - Ao ler, a Página entra em Crm::MetaAdsPage e, na primeira vez, o app assina o campo `feed` dela
#   (Crm::MetaAds::PageSubscription, #2200) para o webhook de comentário novo (Crm::MetaAds::FacebookFeed).
# - Resposta no privado (Private Reply) fica fora: exige pages_messaging (decisão de 25/10 na #2197; é do #2212).
#
# Erros: `ad_not_found`, `comment_not_found`, `needs_login`, `invalid_message`, `meta_unavailable` (rede, 5xx, limite)
# e `meta_refused` (qualquer outra recusa da Meta).
class Crm::MetaAds::FacebookComments
  class Error < Crm::MetaAds::AdManagement::Error; end

  READ = 'pages_read_user_content'.freeze
  MANAGE = 'pages_manage_engagement'.freeze
  NETWORK = 'facebook'.freeze
  FEED = %w[feed].freeze
  # Limite de texto de comentário no Facebook.
  MESSAGE_MAX = 8000

  def initialize(connection)
    @connection = connection
  end

  def list(ad_id)
    return empty('needs_login') unless granted?(READ)

    post_id = post_id_for(ad_id)
    return empty('no_post') if post_id.blank?

    client = page_client(post_id)
    return empty('needs_login') if client.nil?

    data = graph!(client.post_comments(post_id))
    comments = data['comments'].to_h
    {
      status: 'ready', permalink_url: data['permalink_url'], comments: rows(comments['data'], page_id(post_id)),
      total: comments.dig('summary', 'total_count').to_i, next_cursor: next_cursor(comments)
    }
  end

  def more(ad_id, cursor)
    return empty('needs_login') unless granted?(READ)

    post_id = post_id!(ad_id)
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

  # Pela IA (#2212), por post: sem anúncio, o post precisa ser de Página da conta.
  def reply_on_post!(post_id, comment_id, message, actor:)
    reply_to(post_id, comment_id, message, { actor: actor, user: nil, ad_id: nil })
  end

  def hide_on_post!(post_id, comment_id, hidden, actor:)
    hide_in(post_id, comment_id, hidden, { actor: actor, user: nil, ad_id: nil })
  end

  private

  def by_user(ad_id, user)
    { actor: 'user', user: user, ad_id: ad_id }
  end

  def reply_to(post_id, comment_id, message, by)
    text = message.to_s.strip
    raise Error, 'invalid_message' if text.empty? || text.length > MESSAGE_MAX

    { id: act!(post_id, comment_id, 'reply', by) { |client| client.reply_comment(comment_id, text) }['id'] }
  end

  def hide_in(post_id, comment_id, hidden, by)
    act!(post_id, comment_id, hidden ? 'hide' : 'show', by) { |client| client.hide_comment(comment_id, hidden) }
    hidden
  end

  def empty(status)
    { status: status, comments: [], total: 0, next_cursor: nil }
  end

  def user_client
    @user_client ||= Meta::AdsGraphClient.new(access_token: @connection.read_token)
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

  def page_client(post_id)
    @page_clients ||= {}
    page = page_id(post_id)
    return @page_clients[page] if @page_clients.key?(page)

    result = user_client.page_access(page)
    raise Error, 'meta_unavailable' if result.transient?

    data = result.ok ? result.data.to_h : {}
    @page_clients[page] = data['access_token'].present? ? remember_page(page, data) : nil
  end

  # A Página entra no resolvedor do webhook e, na primeira vez nesta conta, o `feed` dela é assinado (a assinatura une
  # os campos: não apaga o leadgen do #2195). Falha aqui não tira a lista da tela.
  def remember_page(page, data)
    client = Meta::AdsGraphClient.new(access_token: data['access_token'])
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

  # `by`: { actor:, user:, ad_id: }. Com anúncio, o post já veio dele; sem, a Página precisa ser da conta.
  def act!(post_id, comment_id, acao, by)
    raise Error, 'comment_not_found' unless comment_of_post?(comment_id, post_id)
    raise Error, 'needs_login' unless granted?(MANAGE)
    raise Error, 'comment_not_found' unless by[:ad_id] || own_page?(post_id)

    client = page_client(post_id) || raise(Error, 'needs_login')
    data = graph!(yield(client))
    record_action(acao, comment_id, by)
    data
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

  def comment_of_post?(comment_id, post_id)
    return false unless comment_id.is_a?(String) && post_id.is_a?(String)

    parts = comment_id.split('_', -1)
    parts.length == 2 && parts.all? { |part| digits?(part) } && parts.first == post_id.split('_').last
  end

  def digits?(text)
    text.present? && text.each_char.all? { |char| char.between?('0', '9') }
  end

  def graph!(result)
    return result.data.to_h if result.ok

    raise Error, result.transient? ? 'meta_unavailable' : 'meta_refused'
  end

  def next_cursor(edge)
    edge.dig('paging', 'cursors', 'after') if edge.dig('paging', 'next').present?
  end

  def rows(data, page)
    manage = granted?(MANAGE)
    Array(data).filter_map { |item| row(item, page, manage) if item.is_a?(Hash) }
  end

  def row(item, page, manage)
    own = item.dig('from', 'id').to_s == page
    {
      id: item['id'], author: { name: item.dig('from', 'name'), is_page: own }, text: item['message'],
      created_time: item['created_time'], hidden: item['is_hidden'] == true,
      can_reply: manage && !own && item['can_comment'] == true, can_hide: manage && item['can_hide'] == true,
      can_delete: manage && item['can_remove'] == true, can_reply_private: false,
      replies: Array(item.dig('comments', 'data')).filter_map { |reply| row(reply, page, manage) if reply.is_a?(Hash) }
    }
  end
end
