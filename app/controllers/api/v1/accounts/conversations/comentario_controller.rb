# Comentários na caixa (#2215): na conversa que nasceu de um comentário do Instagram (#2212), o comentário e as ações
# nele (ConversaCanal::ComentarioDoInstagram). Atrás da flag `meta_ads_comentarios_ia`, a mesma que cria essas conversas;
# sem ela, ou em conversa que não nasceu de comentário do Instagram, 404 (nada chama a Meta).
#
# GET    conversations/:id/comentario            → { status, comentario, pode }. Ler: quem vê a conversa (view?).
# POST   conversations/:id/comentario/responder  content= → responder em público. Quem escreve na conversa (show?).
# POST   conversations/:id/comentario/esconder   hidden=  → esconder ou mostrar de novo. Quem escreve na conversa.
# DELETE conversations/:id/comentario                     → apagar (a tela confirma antes). Só administrador ou função
#        com conversation_message_delete (ConversationPolicy#delete_comment?, #2517); agente sem função não apaga.
#
# O texto vai só em `content`, que o log do Rails já filtra (#2103). Toda ação fica na Auditoria da conta com quem, a
# conversa, o post, o comentário e a ação, nunca o texto.
class Api::V1::Accounts::Conversations::ComentarioController < Api::V1::Accounts::Conversations::BaseController
  AUDIT_ACTION = 'conversation_comment'.freeze
  FLAG = Crm::MetaAds::ComentariosIa::Cuidar::FLAG
  STATUS = { 'comment_not_found' => :not_found }.freeze
  # Só estes valores: o cast do Rails leria qualquer outro texto como true (e esconderia o comentário).
  HIDDEN = [true, false, 'true', 'false'].freeze

  before_action :ensure_flag
  before_action :load_comentario
  before_action -> { authorize @conversation, :delete_comment? }, only: :destroy

  rescue_from ::Crm::MetaAds::InstagramPrivateReply::Error, with: :render_error

  def show
    render json: @comentario.ler.merge(pode: pode)
  end

  def responder
    result = @comentario.responder!(content, user: Current.user)
    audit!('reply')
    render json: result
  end

  def esconder
    return render json: { error: 'invalid_hidden' }, status: :unprocessable_content unless HIDDEN.include?(params[:hidden])

    hidden = ActiveModel::Type::Boolean.new.cast(params[:hidden])
    result = @comentario.esconder!(hidden, user: Current.user)
    audit!(hidden ? 'hide' : 'show')
    render json: result
  end

  def destroy
    result = @comentario.apagar!(user: Current.user)
    audit!('delete')
    render json: result
  end

  private

  def ensure_flag
    head :not_found unless Current.account.feature_enabled?(FLAG)
  end

  def load_comentario
    @comentario = ConversaCanal::ComentarioDoInstagram.da_conversa(@conversation)
    head :not_found if @comentario.nil?
  end

  def pode
    escrever = policy(@conversation).show?
    { responder: escrever, esconder: escrever, apagar: policy(@conversation).delete_comment? }
  end

  # Só texto: lista ou objeto em `content` virariam outro texto no `to_s` e iriam à Meta (#2327).
  def content
    value = params[:content]
    raise ::Crm::MetaAds::InstagramPrivateReply::Error, 'invalid_text' unless value.nil? || value.is_a?(String)

    value.to_s
  end

  def render_error(error)
    render json: { error: error.code }, status: STATUS.fetch(error.code, :unprocessable_content)
  end

  # A Meta já agiu quando isto roda: falha ao gravar a Auditoria vai ao rastreador e a resposta diz a verdade.
  def audit!(action)
    Audited.audit_class.create!(
      auditable: Current.account, user: Current.user, action: AUDIT_ACTION,
      audited_changes: { 'network' => 'instagram', 'conversation_id' => @conversation.display_id, 'post_id' => @comentario.post_id,
                         'comment_id' => @comentario.comment_id, 'action' => action }
    )
  rescue StandardError => e
    Rails.logger.error("[ComentarioDaConversa] auditoria não gravada: account=#{Current.account.id} conversa=#{@conversation.display_id} " \
                       "acao=#{action} #{e.class.name}")
    ChatwootExceptionTracker.new(e, account: Current.account).capture_exception
  end
end
