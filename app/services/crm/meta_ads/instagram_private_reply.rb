# Resposta no privado a um comentário do Instagram (#2196, Private Reply): uma mensagem só, até 7 dias depois do
# comentário, que chega ao Direct da pessoa e continua como conversa na caixa do Instagram. Usada pela tela do anúncio
# (actor `user`) e pela IA dos comentários (#2212, actor `ai`).
#
# Ordem: reivindica a linha em Crm::MetaAdsCommentAction (o índice único barra a segunda vez, inclusive webhook
# reenviado), confere a janela, chama a Meta e só então abre a conversa. A mensagem é gravada com o `message_id` da
# Meta como source_id: o envio da caixa não a manda de novo, e o eco do webhook a reconhece em vez de duplicar. Se a Meta
# recusar, a linha é apagada e o comentário volta a aceitar a resposta.
#
# `comment` vem como a Graph ou o webhook mandam: { 'id', 'timestamp', 'from' => { 'id', 'username' } }.
class Crm::MetaAds::InstagramPrivateReply
  class Error < StandardError
    attr_reader :code

    def initialize(code)
      @code = code
      super(code)
    end
  end

  WINDOW = 7.days
  MAX_TEXT = 1000

  def initialize(channel)
    @channel = channel
  end

  def perform!(comment:, text:, actor:, user: nil, ad_id: nil)
    text = text.to_s.strip
    raise Error, 'invalid_text' if text.blank? || text.length > MAX_TEXT
    raise Error, 'private_reply_expired' unless within_window?(comment['timestamp'])

    action = claim!(comment['id'], actor, user, ad_id)
    result = Instagram::CommentsClient.new(@channel).private_reply(comment['id'], text)
    unless result.ok
      action.destroy!
      raise Error, error_code(result)
    end

    record!(action, comment, text, result.data, user)
  end

  private

  def within_window?(timestamp)
    Time.zone.parse(timestamp.to_s)&.after?(WINDOW.ago)
  rescue ArgumentError
    false
  end

  def claim!(comment_id, actor, user, ad_id)
    Crm::MetaAdsCommentAction.record!(account: @channel.account, network: 'instagram', ad_id: ad_id&.to_s, comment_id: comment_id.to_s,
                                      action: 'private_reply', actor: actor, user: user)
  rescue ActiveRecord::RecordNotUnique
    raise Error, 'private_reply_done'
  end

  def error_code(result)
    return 'needs_login' if result.scope_error? || result.token_invalid?

    result.transient? ? 'meta_unavailable' : 'meta_refused'
  end

  def record!(action, comment, text, sent, user)
    conversation = conversation_for(sent['recipient_id'].to_s, comment.dig('from', 'username'))
    message = conversation.messages.create!(
      account_id: conversation.account_id, inbox_id: conversation.inbox_id, message_type: :outgoing, status: :sent,
      content: text, sender: user, source_id: sent['message_id']
    )
    action.update!(conversation: conversation)
    { conversation: conversation, message: message }
  end

  # A conversa que a pessoa já tem aberta na caixa, como o recebimento do Direct escolhe; senão, uma nova.
  def conversation_for(source_id, username)
    contact_inbox = inbox.contact_inboxes.find_by(source_id: source_id) || new_contact_inbox(source_id, username)
    existing = contact_inbox.conversations.where.not(status: :resolved).order(created_at: :desc).first
    existing || ConversationBuilder.new(params: ActionController::Parameters.new({}), contact_inbox: contact_inbox).perform
  end

  def new_contact_inbox(source_id, username)
    contact_inbox = @channel.create_contact_inbox(source_id, username)
    contact = contact_inbox.contact
    contact.update!(additional_attributes: contact.additional_attributes.merge('social_profiles' => { 'instagram' => username })) if username
    contact_inbox
  end

  def inbox
    @channel.inbox
  end
end
