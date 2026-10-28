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
    status = change_status!(params[:ad_id].to_s, params[:status].to_s)
    audit!(params[:ad_id].to_s, status)
    render json: { status: status }.merge(activation(status))
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

  # Gerenciador simples (#2198, ponto 6): anúncio criado aqui nasceu com os três níveis pausados; ativar liga os três e
  # pausar pausa os três. Outro anúncio: a gestão de sempre, só o anúncio.
  def change_status!(ad_id, status)
    @created = creation_activation.created_here(ad_id) if criar?
    return management.change!(ad_id, status) if @created.nil?

    creation_activation.change!(@created, status)
  end

  # Ao ativar, diz se a campanha ou o grupo seguram o anúncio (`held_by`). Criado aqui: os três acabaram de ser ligados.
  def activation(status)
    return {} unless status == 'ACTIVE' && criar?
    return { held_by: nil } if @created

    { held_by: creation_activation.held_by(params[:ad_id].to_s) }
  end

  def criar?
    Current.account.feature_enabled?('meta_ads_criar')
  end

  def creation_activation
    @creation_activation ||= ::Crm::MetaAds::Creation::Activation.new(@connection, user: Current.user)
  end

  def management
    @management ||= ::Crm::MetaAds::AdManagement.new(@connection)
  end

  # Pausar ou ativar mexe no dinheiro do cliente: fica na Auditoria da conta (o log da aplicação não sobrevive ao
  # deploy). Só ids, nome do anúncio e situação nova; nunca o token. Anúncio criado aqui: também a campanha e o grupo,
  # que mudaram junto. A Meta já mudou o anúncio quando isto roda: falha
  # ao gravar vai para o rastreador de erros e a resposta continua dizendo a verdade (a situação nova), em vez de um 500
  # que faria a pessoa repetir achando que não foi.
  def audit!(ad_id, status)
    Audited.audit_class.create!(
      auditable: Current.account, user: Current.user, action: AUDIT_ACTION,
      audited_changes: { 'ad_id' => ad_id, 'campaign_id' => @created&.campaign_id, 'adset_id' => @created&.adset_id,
                         'ad_name' => management.ad_name(ad_id), 'status' => status }.compact
    )
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: Current.account).capture_exception
  end
end
