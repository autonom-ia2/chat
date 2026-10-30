# As linhas dos comentários do Instagram, na forma da casca comum (MetaAdsComments.vue, #2196), a partir dos fios de
# uma página (Crm::MetaAds::InstagramCommentThreads). Usada pelo comentário do anúncio (Crm::MetaAds::InstagramComments)
# e pelo comentário do post (Seus posts, #2305). Quem chama já conferiu que a pessoa vê a caixa: aqui não há essa
# conferência.
#
# - `can_manage`: sem ele, todos os `can_*` falsos; a lista não oferece ação que o servidor recusaria. Sem padrão: cada
#   tela diz o seu.
# - `conversation_access`: se a pessoa enxerga a conversa do privado. O caminho dela ("Ver conversa") só vai quando sim.
class Crm::MetaAds::InstagramCommentRows
  # Para quem já mostra a conversa a todos que leem os comentários.
  EVERY_CONVERSATION = ->(_conversation) { true }

  def initialize(channel, account_id:, can_manage:, conversation_access:)
    @channel = channel
    @account_id = account_id
    @can_manage = can_manage
    @conversation_access = conversation_access
  end

  def present(threads)
    actions = Crm::MetaAdsCommentAction.where(account_id: @account_id, network: 'instagram', action: 'private_reply',
                                              comment_id: threads.ids)
                                       .includes(:conversation).reject(&:abandoned?).index_by(&:comment_id)
    threads.top.map do |item|
      row(item, actions: actions, own: threads.own?(item))
        .merge(replies: threads.replies(item).map { |reply| row(reply, actions: actions, nested: true, own: threads.own?(reply)) })
    end
  end

  # O privado só vale em comentário de primeiro nível de outra pessoa (`nested`: resposta dentro de um comentário).
  # `own`: é da conta mesmo quando a Graph não traz o `from` (#2313); o @ é o da caixa.
  def row(item, actions:, own:, nested: false)
    username = item.dig('from', 'username') || (@channel.provider_name if own)
    {
      id: item['id'].to_s, author: { name: nil, username: username, is_page: own }, text: item['text'],
      created_time: item['timestamp'], hidden: item['hidden'] == true, replies: [],
      can_reply: @can_manage && !own, can_hide: @can_manage && !own, can_delete: @can_manage
    }.merge(private_state(item, !own && !nested, actions[item['id'].to_s]))
  end

  def conversation_path(conversation)
    return if conversation.nil? || !@conversation_access.call(conversation)

    "/app/accounts/#{conversation.account_id}/conversations/#{conversation.display_id}"
  end

  private

  # Responder no privado: uma vez só (a linha em Crm::MetaAdsCommentAction diz que já foi) e só até 7 dias depois.
  def private_state(item, eligible, action)
    expired = eligible && expired?(item)
    {
      can_reply_private: @can_manage && eligible && !expired && action.nil?, private_reply_expired: expired && action.nil?,
      private_reply: private_reply(action)
    }
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
end
