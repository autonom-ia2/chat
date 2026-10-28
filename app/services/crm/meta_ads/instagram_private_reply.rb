# Resposta no privado a um comentário do Instagram (#2196, Private Reply): uma mensagem só, até 7 dias depois do
# comentário, que chega ao Direct da pessoa e continua como conversa na caixa do Instagram. Usada pela tela do anúncio
# (actor `user`) e pela IA dos comentários (#2212, actor `ai`).
#
# Ordem: reivindica a linha em Crm::MetaAdsCommentAction (o índice único barra a segunda vez, inclusive webhook
# reenviado), confere a janela, chama a Meta e só então abre a conversa. A mensagem é gravada com o `message_id` da
# Meta como source_id: o envio da caixa não a manda de novo, e o eco do webhook a reconhece em vez de duplicar (se o
# eco chegar antes, a mensagem dele é a que fica).
#
# Recusa explícita da Meta (4xx com código): a linha é apagada e o comentário volta a aceitar a resposta. Os estados da
# linha (reservado, sem confirmação, confirmado) estão em Crm::MetaAdsCommentAction: `attempt!` marca que a chamada vai
# sair; falha passageira (rede, tempo esgotado, 5xx) deixa a linha sem confirmação e travada, porque a Meta pode ter
# entregado e um segundo envio seria DM duplicada. A tela mostra "Enviado no privado, sem confirmação do Instagram.
# Confira no Direct." e a ação "Não foi enviado", que só quem gere os anúncios usa. Depois de a Meta aceitar, erro ao
# abrir a conversa não vira falha: vai para o rastreador e a resposta diz que foi.
#
# Só comentário de primeiro nível: resposta a comentário (com `parent_id`) não recebe o privado.
#
# `comment` vem como a Graph ou o webhook mandam: { 'id', 'timestamp', 'parent_id', 'from' => { 'id', 'username' } }.
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
    text = valid_text!(text)
    validate_comment!(comment)
    release_abandoned!(comment['id'])
    action = claim!(comment['id'], actor, user, ad_id)
    raise Error, 'private_reply_retry' unless action.attempt!

    result = Instagram::CommentsClient.new(@channel).private_reply(comment['id'], text)
    unless result.ok
      maybe_delivered?(result) ? action.fail! : action.destroy!
      raise Error, error_code(result)
    end

    confirm_safely!(action)
    record_safely!(action, comment, text, result.data, user)
  end

  private

  # A Meta já aceitou: falha ao gravar a confirmação tenta de novo uma vez e, se insistir, só vai para o log. A linha
  # fica sem confirmação e, passado Crm::MetaAdsCommentAction::IN_FLIGHT, quem gere confere no Direct.
  def confirm_safely!(action)
    attempts = 0
    begin
      attempts += 1
      action.confirm!
    rescue StandardError => e
      retry if attempts < 2
      Rails.logger.error("[InstagramPrivateReply] confirm failed action_id=#{action.id} error=#{e.class.name}")
    end
  end

  def valid_text!(text)
    text = text.to_s.strip
    raise Error, 'invalid_text' if text.blank? || text.length > MAX_TEXT

    text
  end

  def validate_comment!(comment)
    raise Error, 'private_reply_top_only' if comment['parent_id'].present?
    raise Error, 'private_reply_expired' unless within_window?(comment['timestamp'])
  end

  def within_window?(timestamp)
    Time.zone.parse(timestamp.to_s)&.after?(WINDOW.ago)
  rescue ArgumentError
    false
  end

  # Reserva de um envio que nunca saiu (Crm::MetaAdsCommentAction#abandoned?): nada foi enviado, pode refazer.
  def release_abandoned!(comment_id)
    Crm::MetaAdsCommentAction.where(network: 'instagram', comment_id: comment_id.to_s, action: 'private_reply', attempted_at: nil,
                                    confirmed_at: nil, at: ...Crm::MetaAdsCommentAction::RESERVED_TTL.ago).delete_all
  end

  def claim!(comment_id, actor, user, ad_id)
    Crm::MetaAdsCommentAction.record!(account: @channel.account, network: 'instagram', ad_id: ad_id&.to_s, comment_id: comment_id.to_s,
                                      action: 'private_reply', actor: actor, user: user)
  rescue ActiveRecord::RecordNotUnique
    raise Error, 'private_reply_done'
  end

  # Sem resposta (rede, tempo esgotado) ou 5xx: a Meta pode ter entregado. Qualquer 4xx é recusa.
  def maybe_delivered?(result)
    result.network_error? || result.http_code.to_i >= 500
  end

  def error_code(result)
    return 'needs_login' if result.scope_error? || result.token_invalid?

    result.transient? ? 'meta_unavailable' : 'meta_refused'
  end

  def record_safely!(action, comment, text, sent, user)
    return { conversation: nil, message: nil } if sent['message_id'].blank? || sent['recipient_id'].blank?

    record!(action, comment, text, sent, user)
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: @channel.account).capture_exception
    { conversation: nil, message: nil }
  end

  # Sem `message_id` a mensagem não é criada: sem source_id, o envio da caixa mandaria o texto de novo.
  def record!(action, comment, text, sent, user)
    conversation = conversation_for(sent['recipient_id'].to_s, comment.dig('from', 'username'))
    message = Message.find_by(inbox_id: conversation.inbox_id, source_id: sent['message_id']) || conversation.messages.create!(
      account_id: conversation.account_id, inbox_id: conversation.inbox_id, message_type: :outgoing, status: :sent,
      content: text, sender: user, source_id: sent['message_id']
    )
    action.update!(conversation: message.conversation)
    { conversation: message.conversation, message: message }
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
