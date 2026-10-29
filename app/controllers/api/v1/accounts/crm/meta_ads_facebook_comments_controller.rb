# Comentários do anúncio no Facebook (#2197, flag `meta_ads_comentarios_facebook`). Sem a flag, 404: nada aqui chama a
# Meta.
#
# GET    meta_ads_connection/ads/:ad_id/facebook_comments                    → { comments: status, lista, total, cursor }
#        (?after= para a página seguinte). Administrador ou `meta_ads_view`; as linhas só deixam agir
#        (can_reply/can_hide/can_delete) para quem também tem `meta_ads_manage`. Só para esse a leitura guarda a Página
#        e assina o `feed` dela; com só `meta_ads_view`, ler não grava nada (#2359).
# POST   meta_ads_connection/ads/:ad_id/facebook_comments/:comment_id/reply  → content=; responde como a Página. O texto vai em
#        `content`, que o log do Rails já filtra (#2103).
# PATCH  meta_ads_connection/ads/:ad_id/facebook_comments/:comment_id        → hidden=true|false.
# DELETE meta_ads_connection/ads/:ad_id/facebook_comments/:comment_id        → apaga (irreversível; a tela confirma).
# As três ações: administrador ou `meta_ads_manage`.
#
# Ler e agir pedem também ver a caixa do Messenger da Página (InboxPolicy#show?, #2359). Sem ela na conta, a lista vem
# com status `no_inbox` (e agir, 422 `no_inbox`); com ela e sem ser dela, status `not_inbox_member` (agir, 403).
#
# Sem conexão ativa com conta de anúncios: 404 not_connected. Anúncio de outra conta ou comentário de outro post: 404.
# Cada ação fica na Auditoria da conta e em crm_meta_ads_comment_actions (#2196) com pessoa, anúncio, comentário e
# ação — nunca o texto (dado de terceiro) nem o token.
class Api::V1::Accounts::Crm::MetaAdsFacebookCommentsController < Api::V1::Accounts::Crm::BaseController
  AUDIT_ACTION = 'meta_ads_facebook_comment'.freeze
  NOT_FOUND = %w[ad_not_found comment_not_found].freeze
  FORBIDDEN = %w[not_inbox_member].freeze
  ACTION_FLAGS = %i[can_reply can_hide can_delete].freeze

  before_action :ensure_feature
  before_action :ensure_view
  before_action :ensure_manage, except: [:index]
  before_action :load_connection

  def index
    result = params[:after].present? ? comments.more(ad_id, params[:after]) : comments.list(ad_id)
    render json: { comments: manage? ? result : without_actions(result) }
  rescue ::Crm::MetaAds::FacebookComments::Error => e
    render_error(e.code)
  end

  def reply
    return render_unprocessable('invalid_text') unless params[:content].is_a?(String)

    result = comments.reply!(ad_id, comment_id, params[:content], user: Current.user)
    audit!('reply')
    render json: result
  rescue ::Crm::MetaAds::FacebookComments::Error => e
    render_error(e.code)
  end

  # `hidden` precisa vir true ou false: sem ele, mostrar por engano deixaria público um comentário que alguém ocultou.
  def update
    return render_unprocessable('invalid_hidden') unless [true, false].include?(params[:hidden])

    hidden = comments.hide!(ad_id, comment_id, params[:hidden], user: Current.user)
    audit!(hidden ? 'hide' : 'show')
    render json: { hidden: hidden }
  rescue ::Crm::MetaAds::FacebookComments::Error => e
    render_error(e.code)
  end

  def destroy
    comments.delete!(ad_id, comment_id, user: Current.user)
    audit!('delete')
    render json: { deleted: true }
  rescue ::Crm::MetaAds::FacebookComments::Error => e
    render_error(e.code)
  end

  private

  def ensure_feature
    head :not_found unless Current.account.feature_enabled?('meta_ads_comentarios_facebook')
  end

  def ensure_view
    render json: { error: 'forbidden' }, status: :forbidden unless policy.show?
  end

  def ensure_manage
    render json: { error: 'forbidden' }, status: :forbidden unless manage?
  end

  def manage?
    policy.update?
  end

  def policy
    @policy ||= Pundit.policy!(pundit_user, ::Crm::MetaAdsConnection)
  end

  def load_connection
    @connection = ::Crm::MetaAdsConnection.active.find_by(account_id: Current.account.id)
    render json: { error: 'not_connected' }, status: :not_found if @connection&.ad_account_id.blank?
  end

  def comments
    @comments ||= ::Crm::MetaAds::FacebookComments.new(
      @connection, inbox_access: ->(inbox) { Pundit.policy!(pundit_user, inbox).show? }, can_manage: manage?
    )
  end

  def ad_id
    params[:ad_id].to_s
  end

  def comment_id
    params[:comment_id].to_s
  end

  def render_error(code)
    return render json: { error: code }, status: :not_found if NOT_FOUND.include?(code)
    return render json: { error: code }, status: :forbidden if FORBIDDEN.include?(code)

    render_unprocessable(code)
  end

  def without_actions(result)
    result.merge(comments: result[:comments].map { |row| row_without_actions(row) })
  end

  def row_without_actions(row)
    row.merge(ACTION_FLAGS.index_with(false)).merge(replies: row[:replies].map { |reply| row_without_actions(reply) })
  end

  # A Meta já agiu quando isto roda: falha ao gravar vai ao rastreador de erros e a resposta continua dizendo a verdade
  # (como no pausar do #2161).
  def audit!(acao)
    Audited.audit_class.create!(
      auditable: Current.account, user: Current.user, action: AUDIT_ACTION,
      audited_changes: { 'ad_id' => ad_id, 'comment_id' => comment_id, 'acao' => acao }
    )
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: Current.account).capture_exception
  end
end
