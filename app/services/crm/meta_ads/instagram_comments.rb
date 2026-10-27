# Comentários do anúncio no Instagram (#2196), para a aba Instagram do detalhe do anúncio. O criativo diz a mídia do
# anúncio no Instagram (`effective_instagram_media_id`) e a conta que o publica (`instagram_user_id`); a caixa do
# Instagram da conta com esse id lê e age pela Graph do login do Instagram (Instagram::CommentsClient). Nada do
# comentário é gravado: é dado de terceiro, lido ao vivo.
#
# `payload` → { status, account, permalink_url, comments, total, next_cursor }, na forma do adaptador da tela:
# - `ready`: a lista; `no_post`: o anúncio não aparece no Instagram;
# - `not_connected`: o Instagram do anúncio não tem caixa nesta conta;
# - `needs_login`: a caixa existe, mas sem a permissão de comentários (ou esperando nova autorização); vem com o
#   `inbox_id`, que a tela usa para pedir o login de novo (Instagram::IntegrationHelper::REAUTH_PURPOSES).
# nil quando o anúncio não é da conta de anúncios da conexão (a tela trata como inexistente).
#
# Cada ação confere antes que o comentário é da mídia do anúncio: sem isso, quem gere os anúncios agiria em qualquer
# comentário do Instagram da caixa pelo id. Erros (Error#code): `ad_not_found`, `no_post`, `not_connected`,
# `comment_not_found`, `invalid_text`, `needs_login`, `meta_unavailable`, `meta_refused`, `not_inbox_member` e os do
# privado (Crm::MetaAds::InstagramPrivateReply).
#
# Responder no privado cria contato, conversa e mensagem na caixa do Instagram em nome de quem clicou: além de gerir os
# anúncios, pede ser da caixa (`inbox_access`, InboxPolicy#show? de quem chama, parecer da sessão Funções). Quem não é
# vê `private_reply_not_member` no lugar do botão. Quem só vê os anúncios (`can_manage: false`) recebe todos os `can_*`
# falsos: a lista não oferece ação que o servidor recusaria.
class Crm::MetaAds::InstagramComments
  Error = Crm::MetaAds::InstagramPrivateReply::Error

  MAX_TEXT = 2200

  def initialize(connection, inbox_access:, can_manage:)
    @connection = connection
    @inbox_access = inbox_access
    @can_manage = can_manage
  end

  def payload(ad_id, after: nil)
    target = target(ad_id)
    return if target.nil?
    return empty(target) unless target[:status] == 'ready'

    channel = target[:channel]
    result = client(channel).comments(target[:media_id], after: after)
    return empty(target.merge(status: 'needs_login')) if login_error?(result)
    raise Error, failure(result) unless result.ok

    rows = Array(result.data['data'])
    {
      status: 'ready', account: target[:account], permalink_url: target[:permalink_url],
      comments: present(rows, channel), total: total(channel, target[:media_id], rows), next_cursor: next_cursor(result.data)
    }
  end

  # No Instagram a resposta fica num nível só: responder a uma resposta vai para o comentário de cima, como no app.
  def reply!(ad_id, comment_id, text)
    text = valid_text!(text, MAX_TEXT)
    found = comment_of_ad!(ad_id, comment_id)
    channel = found[:channel]
    result = client(channel).reply(found[:comment]['parent_id'].presence || comment_id, text)
    raise Error, failure(result) unless result.ok

    row({ 'id' => result.data['id'].to_s, 'text' => text, 'timestamp' => Time.current.iso8601,
          'from' => { 'id' => channel.instagram_id, 'username' => channel.provider_name } }, channel, actions: {})
  end

  def hide!(ad_id, comment_id, hidden:)
    channel = comment_of_ad!(ad_id, comment_id)[:channel]
    result = client(channel).hide(comment_id, hidden: hidden)
    raise Error, failure(result) unless result.ok

    { id: comment_id, hidden: hidden }
  end

  # Irreversível: some do Instagram. A tela confirma antes.
  def delete!(ad_id, comment_id)
    channel = comment_of_ad!(ad_id, comment_id)[:channel]
    result = client(channel).delete(comment_id)
    raise Error, failure(result) unless result.ok

    { id: comment_id }
  end

  def private_reply!(ad_id, comment_id, text, user:)
    valid_text!(text, Crm::MetaAds::InstagramPrivateReply::MAX_TEXT)
    target = ready_target!(ad_id)
    raise Error, 'not_inbox_member' unless member?(target[:channel])

    found = comment_of!(target, comment_id)
    sent = Crm::MetaAds::InstagramPrivateReply.new(found[:channel]).perform!(comment: found[:comment], text: text, actor: 'user', user: user,
                                                                             ad_id: ad_id)
    { sent_at: Time.current.iso8601, conversation_path: conversation_path(sent[:conversation]) }
  end

  # "Não foi enviado": quem gere os anúncios conferiu no Direct que o privado sem confirmação não chegou e libera o
  # botão. Só a linha sem confirmação deste anúncio, nesta conta, e nunca com o envio em andamento
  # (Crm::MetaAdsCommentAction#releasable?); não chama a Meta.
  def release_private_reply!(ad_id, comment_id)
    action = Crm::MetaAdsCommentAction.find_by(account_id: @connection.account_id, network: 'instagram', action: 'private_reply',
                                               comment_id: comment_id.to_s, ad_id: ad_id.to_s, confirmed_at: nil)
    raise Error, 'private_reply_not_pending' if action.nil? || !action.releasable?

    action.destroy!
    { id: comment_id.to_s }
  end

  private

  def target(ad_id)
    ad = management.ad(ad_id.to_s)
    return if ad.nil?

    creative = ad['creative'].to_h
    return { status: 'no_post' } if creative['effective_instagram_media_id'].blank?

    channel_target(creative)
  rescue Crm::MetaAds::AdManagement::Error => e
    raise Error, e.code
  end

  def channel_target(creative)
    instagram_user_id = creative['instagram_user_id'].to_s
    channel = Channel::Instagram.find_by(account_id: @connection.account_id, instagram_id: instagram_user_id)
    return { status: 'not_connected', account: { username: ad_account_username(instagram_user_id), name: nil } } if channel.nil?

    target = { status: 'ready', account: { username: channel.provider_name, name: channel.inbox&.name }, inbox_id: channel.inbox&.id }
    return target.merge(status: 'needs_login') if channel.reauthorization_required?

    target.merge(channel: channel, media_id: creative['effective_instagram_media_id'].to_s,
                 permalink_url: creative['instagram_permalink_url'])
  end

  def comment_of_ad!(ad_id, comment_id)
    comment_of!(ready_target!(ad_id), comment_id)
  end

  def ready_target!(ad_id)
    target = target(ad_id)
    raise Error, 'ad_not_found' if target.nil?
    raise Error, target[:status] unless target[:status] == 'ready'

    target
  end

  def comment_of!(target, comment_id)
    result = client(target[:channel]).comment(comment_id)
    raise Error, 'needs_login' if login_error?(result)
    raise Error, 'comment_not_found' if !result.ok || result.data.dig('media', 'id').to_s != target[:media_id]

    { channel: target[:channel], comment: result.data }
  end

  def empty(target)
    payload = { status: target[:status], account: target[:account], comments: [], total: 0, next_cursor: nil }
    target[:status] == 'needs_login' ? payload.merge(inbox_id: target[:inbox_id]) : payload
  end

  def present(rows, channel)
    actions = Crm::MetaAdsCommentAction.where(account_id: @connection.account_id, network: 'instagram', action: 'private_reply',
                                              comment_id: rows.flat_map { |item| [item['id'], *replies(item).pluck('id')] })
                                       .includes(:conversation).reject(&:abandoned?).index_by(&:comment_id)
    rows.map do |item|
      row(item, channel, actions: actions).merge(replies: replies(item).map { |reply| row(reply, channel, actions: actions, nested: true) })
    end
  end

  def replies(item)
    Array(item.dig('replies', 'data'))
  end

  # O privado só vale em comentário de primeiro nível de outra pessoa (`nested`: resposta dentro de um comentário).
  def row(item, channel, actions:, nested: false)
    own = item.dig('from', 'id').to_s == channel.instagram_id
    {
      id: item['id'].to_s, author: { name: nil, username: item.dig('from', 'username'), is_page: own }, text: item['text'],
      created_time: item['timestamp'], hidden: item['hidden'] == true, replies: [],
      can_reply: @can_manage && !own, can_hide: @can_manage && !own, can_delete: @can_manage
    }.merge(private_state(item, !own && !nested, actions[item['id'].to_s], member?(channel)))
  end

  def member?(channel)
    @member ||= {}
    @member.fetch(channel.id) { @member[channel.id] = @inbox_access.call(channel.inbox) == true }
  end

  # Responder no privado: uma vez só (a linha em Crm::MetaAdsCommentAction diz que já foi) e só até 7 dias depois.
  def private_state(item, eligible, action, member)
    expired = eligible && expired?(item)
    open = private_open?(eligible, expired, action)
    {
      can_reply_private: open && member, private_reply_not_member: open && !member, private_reply_expired: expired && action.nil?,
      private_reply: private_reply(action)
    }
  end

  def private_open?(eligible, expired, action)
    @can_manage && eligible && !expired && action.nil?
  end

  def private_reply(action)
    return if action.nil?

    { sent_at: action.at.iso8601, confirmed: action.confirmed_at.present?, conversation_path: conversation_path(action.conversation),
      can_release: @can_manage && action.releasable? }
  end

  def expired?(item)
    created = Time.zone.parse(item['timestamp'].to_s)
    created.present? && created.before?(Crm::MetaAds::InstagramPrivateReply::WINDOW.ago)
  end

  def next_cursor(data)
    data.dig('paging', 'cursors', 'after') if data.dig('paging', 'next').present?
  end

  def conversation_path(conversation)
    return if conversation.nil?

    "/app/accounts/#{conversation.account_id}/conversations/#{conversation.display_id}"
  end

  # Total de comentários da mídia como a Meta conta; sem ele, o que veio nesta página.
  def total(channel, media_id, rows)
    result = client(channel).comments_count(media_id)
    return result.data['comments_count'].to_i if result.ok && result.data.key?('comments_count')

    rows.sum { |item| 1 + replies(item).size }
  end

  # O @ do Instagram do anúncio quando ele não tem caixa: só para o texto da tela, pelo token da conexão.
  def ad_account_username(instagram_user_id)
    return if instagram_user_id.blank?

    result = Meta::AdsGraphClient.new(access_token: @connection.read_token).object(instagram_user_id, fields: 'username')
    result.data['username'] if result.ok
  end

  def valid_text!(text, limit)
    text = text.to_s.strip
    raise Error, 'invalid_text' if text.blank? || text.length > limit

    text
  end

  def login_error?(result)
    !result.ok && (result.scope_error? || result.token_invalid?)
  end

  def failure(result)
    return 'needs_login' if login_error?(result)

    result.transient? ? 'meta_unavailable' : 'meta_refused'
  end

  def client(channel)
    Instagram::CommentsClient.new(channel)
  end

  def management
    @management ||= Crm::MetaAds::AdManagement.new(@connection)
  end
end
