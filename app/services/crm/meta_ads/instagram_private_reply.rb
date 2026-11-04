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
# Só comentário de primeiro nível: resposta a comentário (com `parent_id`) não recebe o privado. Com a flag
# meta_ads_comentarios_ia (#2454), a resposta também vai à Meta, que decide; o teste real é do próprio produto,
# na conta piloto. O resultado de cada envio de 2º nível fica consultável, sem texto de terceiro: aceito, a linha
# private_reply guarda o `meta_message_id`; recusado (4xx com código da Meta), a linha sai como sempre e uma
# `private_reply_failed` guarda o código e o subcódigo (`meta_error_code`, `meta_error_subcode`), que também vão no Error. Falha passageira segue
# a regra de sempre (sem confirmação e travada). Sem a flag, `private_reply_top_only`, como antes.
#
# O privado de uma pessoa (actor `user`) também marca quem comentou naquele post (Crm::MetaAdsCommentPerson, #2212),
# antes de chamar a Meta: enquanto o envio sai, a IA não manda outro privado à mesma pessoa no mesmo post. A marca não
# trava a pessoa da equipe: se já existe (a IA ou outro privado chegou antes), o envio segue e a marca de antes fica.
# Recusa 4xx apaga só a marca deste envio; "pode ter saído" a mantém. A IA reserva a sua marca no Registro.
#
# `comment` vem como a Graph ou o webhook mandam: { 'id', 'timestamp', 'parent_id', 'from' => { 'id', 'username' },
# 'media' => { 'id' } }.
class Crm::MetaAds::InstagramPrivateReply
  # `meta_code`, `meta_subcode` e `meta_http`: os da Meta na recusa, para quem chama decidir sem ler a mensagem dela.
  class Error < StandardError
    attr_reader :code, :meta_code, :meta_subcode, :meta_http

    def initialize(code, meta_code: nil, meta_subcode: nil, meta_http: nil)
      @code = code
      @meta_code = meta_code
      @meta_subcode = meta_subcode
      @meta_http = meta_http
      super(code)
    end
  end

  # A flag que deixa a resposta a comentário (2º nível) ir à Meta (#2454): a da IA cuida dos comentários.
  RESPOSTAS = Crm::MetaAds::ComentariosIa::Cuidar::FLAG

  WINDOW = 7.days

  # O texto do privado, conferido antes de qualquer chamada à Meta: vazio é `invalid_text`; acima do limite,
  # `text_too_long`. O limite é o de Crm::MetaAdsCommentCare::MESSAGE_LIMIT, em bytes UTF-8 como a Meta conta (#2543):
  # 700 letras com acento já passam de 1000 bytes. Quem chama antes de ler o comentário (gaveta do anúncio, Seus posts)
  # usa este mesmo método.
  def self.valid_text!(text)
    text = text.to_s.strip
    raise Error, 'invalid_text' if text.blank?
    raise Error, 'text_too_long' if text.bytesize > Crm::MetaAdsCommentCare::MESSAGE_LIMIT

    text
  end

  def initialize(channel)
    @channel = channel
  end

  def perform!(comment:, text:, actor:, user: nil, ad_id: nil)
    text = self.class.valid_text!(text)
    validate_comment!(comment)
    release_abandoned!(comment['id'])
    action = claim!(comment['id'], actor, user, ad_id)
    person_id = mark_person!(action, comment) unless actor == Crm::MetaAds::ComentariosIa::Registro::ACTOR
    unless action.attempt!
      release_person!(person_id)
      raise Error, 'private_reply_retry'
    end

    result = send!(action, comment, text, person_id)
    confirm_safely!(action)
    accepted_safely!(action, result.data) if second_level?(comment)
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

  def send!(action, comment, text, person_id)
    result = Instagram::CommentsClient.new(@channel).private_reply(comment['id'], text)
    return result if result.ok

    if maybe_delivered?(result)
      action.fail!
    else
      action.destroy!
      release_person!(person_id)
      refused_safely!(action, result) if second_level?(comment) && result.error_code
    end
    raise Error.new(error_code(result), meta_code: result.error_code, meta_subcode: result.error_subcode, meta_http: result.http_code)
  end

  def second_level?(comment)
    comment['parent_id'].present?
  end

  # O resultado do envio de 2º nível (#2454) é só registro: falha ao gravar vai para o rastreador e não muda o envio.
  def accepted_safely!(action, sent)
    action.update!(meta_message_id: sent['message_id'].presence&.to_s)
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: @channel.account).capture_exception
  end

  def refused_safely!(action, result)
    Crm::MetaAdsCommentAction.record!(account: @channel.account, network: 'instagram', ad_id: action.ad_id, comment_id: action.comment_id,
                                      action: 'private_reply_failed', actor: action.actor, user: action.user,
                                      meta_error_code: result.error_code, meta_error_subcode: result.error_subcode)
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: @channel.account).capture_exception
  end

  # Devolve o id da marca quando ela é deste envio; nil quando já existia ou falta post ou quem comentou. Nada saiu
  # ainda: erro ao gravar solta a reserva do comentário e sobe.
  def mark_person!(action, comment)
    post_id = comment.dig('media', 'id').to_s
    from_id = comment.dig('from', 'id').to_s
    return if post_id.empty? || from_id.empty?

    Crm::MetaAdsCommentPerson.insert_all( # rubocop:disable Rails/SkipsModelValidations
      [{ account_id: @channel.account_id, network: 'instagram', post_id: post_id, from_id: from_id, comment_id: comment['id'].to_s }],
      unique_by: :idx_crm_meta_ads_comment_people_once, returning: %i[id]
    ).rows.first&.first
  rescue StandardError
    action.destroy!
    raise
  end

  def release_person!(person_id)
    Crm::MetaAdsCommentPerson.where(id: person_id).delete_all if person_id
  end

  def validate_comment!(comment)
    raise Error, 'private_reply_top_only' if second_level?(comment) && !@channel.account.feature_enabled?(RESPOSTAS)
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
