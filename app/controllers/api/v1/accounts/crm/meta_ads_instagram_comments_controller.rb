# Comentários do anúncio no Instagram (#2196, flags `meta_ads_gestao` e `meta_ads_comentarios_instagram`). Sem as
# flags, 404: nada aqui chama a Meta.
#
# GET    meta_ads_connection/ads/:ad_id/instagram_comments?after=          → comentários (Crm::MetaAds::InstagramComments).
#        Ver: administrador ou `meta_ads_view`, e ver a caixa do Instagram (InboxPolicy#show?). Sem ver a caixa,
#        `status: not_inbox_member` e nenhum comentário (#2358).
# POST   .../instagram_comments/:comment_id/reply          content=        → responder em público.
# POST   .../instagram_comments/:comment_id/hide           hidden=         → ocultar ou mostrar de novo.
# POST   .../instagram_comments/:comment_id/private_reply  content=        → responder no privado (Private Reply).
#        O texto vai em `content`, que o log do Rails já filtra (#2103, #2327); `text` sairia em claro no CloudWatch.
# POST   .../instagram_comments/:comment_id/private_reply/release          → "Não foi enviado": libera o privado sem
#        confirmação da Meta (Crm::MetaAdsCommentAction), depois de a pessoa conferir no Direct.
# DELETE .../instagram_comments/:comment_id                                → apagar (a tela confirma antes).
#        Agir: administrador ou `meta_ads_manage`, e ver a caixa do Instagram (InboxPolicy#show?), a mesma regra de Seus
#        posts (#2358). Sem ver: 403 `not_inbox_member`, antes de chamar o Instagram.
#
# Erros de regra: 422 com { error: code }; comentário de outra mídia ou anúncio de outra conta: 404. Toda ação fica
# na Auditoria da conta com quem, o anúncio, o comentário e a ação (nunca o texto: o do
# comentário é de terceiro e o da resposta já fica na conversa ou no próprio Instagram).
class Api::V1::Accounts::Crm::MetaAdsInstagramCommentsController < Api::V1::Accounts::Crm::BaseController
  AUDIT_ACTION = 'meta_ads_comment'.freeze
  STATUS = { 'ad_not_found' => :not_found, 'comment_not_found' => :not_found, 'not_inbox_member' => :forbidden }.freeze

  before_action :ensure_feature
  before_action :ensure_view
  before_action :ensure_manage, except: [:index]
  before_action :ensure_ids
  before_action :load_connection

  rescue_from ::Crm::MetaAds::InstagramComments::Error, with: :render_error

  def index
    payload = comments.payload(ad_id, after: params[:after].presence&.to_s)
    return render json: { error: 'ad_not_found' }, status: :not_found if payload.nil?

    render json: payload
  end

  def reply
    result = comments.reply!(ad_id, comment_id, content, user: Current.user)
    audit!('reply')
    render json: result
  end

  def hide
    hidden = ActiveModel::Type::Boolean.new.cast(params[:hidden])
    return render json: { error: 'invalid_hidden' }, status: :unprocessable_content unless [true, false].include?(hidden)

    result = comments.hide!(ad_id, comment_id, hidden: hidden)
    audit!(hidden ? 'hide' : 'show')
    render json: result
  end

  def destroy
    result = comments.delete!(ad_id, comment_id)
    audit!('delete')
    render json: result
  end

  def private_reply
    result = comments.private_reply!(ad_id, comment_id, content, user: Current.user)
    audit!('private_reply')
    render json: result
  end

  def release_private_reply
    result = comments.release_private_reply!(ad_id, comment_id)
    audit!('private_reply_release')
    render json: result
  end

  private

  def ensure_feature
    head :not_found unless Current.account.feature_enabled?('meta_ads_gestao') &&
                           Current.account.feature_enabled?('meta_ads_comentarios_instagram')
  end

  def ensure_view
    render json: { error: 'forbidden' }, status: :forbidden unless policy.show?
  end

  def ensure_manage
    render json: { error: 'forbidden' }, status: :forbidden unless policy.update?
  end

  def policy
    @policy ||= Pundit.policy!(pundit_user, ::Crm::MetaAdsConnection)
  end

  # Os ids entram no caminho da Graph: só dígitos, para que `?`, `/` ou `&` (o Rails decodifica %3F, %2F…) não virem
  # outro caminho ou parâmetros extras na chamada à Meta.
  def ensure_ids
    ids = [ad_id, (comment_id if params.key?(:comment_id))].compact
    render json: { error: 'ad_not_found' }, status: :not_found unless ids.all? { |id| digits?(id) }
  end

  def digits?(value)
    value.present? && value.each_char.all? { |char| char.between?('0', '9') }
  end

  def load_connection
    @connection = ::Crm::MetaAdsConnection.active.find_by(account_id: Current.account.id)
    render json: { error: 'not_connected' }, status: :not_found if @connection&.ad_account_id.blank?
  end

  def comments
    @comments ||= ::Crm::MetaAds::InstagramComments.new(
      @connection, inbox_access: ->(inbox) { inbox.present? && Pundit.policy!(pundit_user, inbox).show? }, can_manage: policy.update?
    )
  end

  def ad_id
    params[:ad_id].to_s
  end

  def comment_id
    params[:comment_id].to_s
  end

  # Só texto: lista ou objeto em `content` virariam outro texto no `to_s` e iriam à Meta (#2327).
  def content
    value = params[:content]
    raise ::Crm::MetaAds::InstagramComments::Error, 'invalid_text' unless value.nil? || value.is_a?(String)

    value.to_s
  end

  def render_error(error)
    render json: { error: error.code }, status: STATUS.fetch(error.code, :unprocessable_content)
  end

  # A Meta já agiu quando isto roda: falha ao gravar vai para o rastreador de erros e a resposta continua dizendo a
  # verdade, em vez de um 500 que faria a pessoa repetir (mesma regra da gestão do anúncio, #2161).
  def audit!(action)
    Audited.audit_class.create!(
      auditable: Current.account, user: Current.user, action: AUDIT_ACTION,
      audited_changes: { 'network' => 'instagram', 'ad_id' => ad_id, 'comment_id' => comment_id, 'action' => action }
    )
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: Current.account).capture_exception
  end
end
