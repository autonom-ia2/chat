# Comentários do post da Página por trás do anúncio, no Facebook (#2197): ler, responder como a Página, ocultar e
# apagar. Chama a Meta ao vivo; nada aqui é gravado (comentário é dado de terceiro).
#
# - Só o post do anúncio da conta de anúncios da conexão (Crm::MetaAds::AdManagement#ad): anúncio de outra conta é
#   `ad_not_found`.
# - Tudo com o token da Página, pedido com o token da pessoa. Ler exige `pages_read_user_content`; responder, ocultar e
#   apagar, `pages_manage_engagement`. Sem a primeira (ou no modo `partner`, em que o token é o da plataforma), a aba
#   pede para entrar de novo com o Facebook (`needs_login`); sem a segunda, lê e não age.
# - Só age em comentário do post do anúncio. O id de comentário da Graph é `<id do post>_<id do comentário>`, em que
#   o id do post é a parte depois do `_` do id do post da Página (`<página>_<post>`); vale também para as respostas.
#   Qualquer outro formato é `comment_not_found`, sem chamar a Meta.
# - Resposta no privado (Private Reply) fica fora: exige pages_messaging (decisão de 25/10 na #2197).
#
# Erros: `ad_not_found`, `comment_not_found`, `needs_login`, `invalid_message`, `meta_unavailable` (rede, 5xx, limite)
# e `meta_refused` (qualquer outra recusa da Meta).
class Crm::MetaAds::FacebookComments
  class Error < Crm::MetaAds::AdManagement::Error; end

  READ = 'pages_read_user_content'.freeze
  MANAGE = 'pages_manage_engagement'.freeze
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
    raise Error, 'needs_login' unless granted?(READ)

    post_id = post_id!(ad_id)
    data = graph!(page_client!(post_id).more_post_comments(post_id, cursor.to_s))
    { comments: rows(data['data'], page_id(post_id)), next_cursor: next_cursor(data) }
  end

  def reply!(ad_id, comment_id, message)
    text = message.to_s.strip
    raise Error, 'invalid_message' if text.empty? || text.length > MESSAGE_MAX

    client = manage_client!(ad_id, comment_id)
    { id: graph!(client.reply_comment(comment_id, text))['id'] }
  end

  def hide!(ad_id, comment_id, hidden)
    graph!(manage_client!(ad_id, comment_id).hide_comment(comment_id, hidden == true))
    hidden == true
  end

  def delete!(ad_id, comment_id)
    graph!(manage_client!(ad_id, comment_id).delete_comment(comment_id))
    true
  end

  private

  def empty(status)
    { status: status, comments: [], total: 0, next_cursor: nil }
  end

  def user_client
    @user_client ||= Meta::AdsGraphClient.new(access_token: @connection.read_token)
  end

  def granted?(permission)
    return false unless @connection.own_token?

    @granted ||= begin
      result = user_client.permissions
      entries = result.ok ? Array(result.data.to_h['data']) : []
      entries.filter_map { |entry| entry['permission'] if entry.is_a?(Hash) && entry['status'] == Meta::AdsGraphClient::GRANTED }
    end
    @granted.include?(permission)
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
    return @page_clients[post_id] if @page_clients.key?(post_id)

    result = user_client.page_access_token(page_id(post_id))
    token = result.data.to_h['access_token'] if result.ok
    @page_clients[post_id] = token.present? ? Meta::AdsGraphClient.new(access_token: token) : nil
  end

  def page_client!(post_id)
    page_client(post_id) || raise(Error, 'needs_login')
  end

  def manage_client!(ad_id, comment_id)
    raise Error, 'needs_login' unless granted?(MANAGE)

    post_id = post_id!(ad_id)
    raise Error, 'comment_not_found' unless comment_of_post?(comment_id, post_id)

    page_client!(post_id)
  end

  def comment_of_post?(comment_id, post_id)
    return false unless comment_id.is_a?(String)

    parts = comment_id.split('_', -1)
    parts.length == 2 && parts.all? { |part| digits?(part) } && parts.first == post_id.to_s.split('_').last
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
