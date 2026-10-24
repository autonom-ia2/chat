# Gestão mínima do anúncio (#2161, flag `meta_ads_gestao`). Sem a flag, 404: nada aqui chama a Meta.
#
# GET  meta_ads_connection/ads/:ad_id/management → situação do anúncio e post da Página (Crm::MetaAds::AdManagement).
#      Ver: administrador ou `meta_ads_view`; `can_change` só vem true para quem também pode mudar (`meta_ads_manage`).
# POST meta_ads_connection/ads/:ad_id/status      → status=ACTIVE|PAUSED. Administrador ou `meta_ads_manage`.
# GET  meta_ads_connection/pages                  → Páginas que a pessoa concedeu ao entrar com o Facebook.
#
# Sem conexão ativa com conta de anúncios: 404 not_connected. Anúncio de outra conta de anúncios: 404 ad_not_found.
# Cada mudança fica na Auditoria da conta com pessoa, anúncio e situação nova (nunca o token).
class Api::V1::Accounts::Crm::MetaAdsAdManagementController < Api::V1::Accounts::Crm::BaseController
  AUDIT_ACTION = 'meta_ads_ad_status'.freeze

  before_action :ensure_feature
  before_action :ensure_view
  before_action :ensure_manage, only: [:status]
  before_action :load_connection

  def show
    payload = management.payload(params[:ad_id].to_s)
    return render json: { error: 'ad_not_found' }, status: :not_found if payload.nil?

    render json: { management: payload.merge(can_change: payload[:can_change] && manage?) }
  rescue ::Crm::MetaAds::AdManagement::Error => e
    render_unprocessable(e.code)
  end

  def status
    status = management.change!(params[:ad_id].to_s, params[:status].to_s)
    audit!(params[:ad_id].to_s, status)
    render json: { status: status }
  rescue ::Crm::MetaAds::AdManagement::Error => e
    return render json: { error: e.code }, status: :not_found if e.code == 'ad_not_found'

    render_unprocessable(e.code)
  end

  def pages
    render json: { pages: management.pages }
  end

  private

  def ensure_feature
    head :not_found unless Current.account.feature_enabled?('meta_ads_gestao')
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

  def management
    @management ||= ::Crm::MetaAds::AdManagement.new(@connection)
  end

  # Pausar ou ativar mexe no dinheiro do cliente: fica na Auditoria da conta (o log da aplicação não sobrevive ao
  # deploy). Só id, nome do anúncio e situação nova; nunca o token.
  def audit!(ad_id, status)
    Audited.audit_class.create!(
      auditable: Current.account, user: Current.user, action: AUDIT_ACTION,
      audited_changes: { 'ad_id' => ad_id, 'ad_name' => management.ad_name(ad_id), 'status' => status }.compact
    )
  end
end
