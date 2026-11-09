# Cuidar do anúncio (#2778, flag `meta_ads_criar`): duplicar e trocar a foto ou o texto. Sem a flag, 404: nada aqui chama
# a Meta. Só anúncio criado pelo Chat2You nesta conta de anúncios (opção a do Rodrigo, 09/11); outro anúncio: 404
# ad_not_found, e a tela diz para usar o Gerenciador de Anúncios.
#
# POST meta_ads_connection/ads/:ad_id/copies   → { idempotency_key, creative?: { text, media? }, recreate_unconfirmed? }
#                                                → cópia pausada da campanha, com orçamento próprio:
#                                                { ad_id, name, status, budget, in_review } (Crm::MetaAds::Creation::Copy).
#                                                `recreate_unconfirmed`: refaz a cópia não confirmada desta chave (#2804).
# PUT  meta_ads_connection/ads/:ad_id/creative → { idempotency_key, text, media? } → { effective_status }
#                                                (Crm::MetaAds::Creation::CreativeSwap). A Meta recusou trocar neste
#                                                anúncio: 422 `swap_refused`, e a tela oferece a cópia.
#
# Administrador ou `meta_ads_manage`. O que muda fica na Auditoria da conta com quem fez (nunca o token). Sem conexão
# ativa com conta de anúncios: 404 not_connected. Mesma chave em andamento: 409 in_progress.
class Api::V1::Accounts::Crm::MetaAdsAdCareController < Api::V1::Accounts::Crm::BaseController
  COPIED_ACTION = ::Crm::MetaAds::Creation::Copy::COPIED_ACTION
  SWAPPED_ACTION = 'meta_ads_creative_swapped'.freeze

  before_action :ensure_feature
  before_action :ensure_manage
  before_action :load_connection

  rescue_from ::Crm::MetaAds::Creation::Error, with: :render_care_error

  def copy
    service = ::Crm::MetaAds::Creation::Copy.new(@connection, user: Current.user)
    copied = service.copy!(params[:ad_id].to_s, copy_params)
    audit_copy!(copied) if service.created_now
    render json: copied
  end

  def creative
    service = ::Crm::MetaAds::Creation::CreativeSwap.new(@connection)
    swapped = service.swap!(params[:ad_id].to_s, creative_params)
    audit!(SWAPPED_ACTION, 'ad_id' => params[:ad_id].to_s, 'new_media' => creative_params[:media].present?) if service.swapped_now
    render json: swapped
  end

  private

  def copy_params
    params.permit(:idempotency_key, :recreate_unconfirmed, creative: [:text, { media: [:kind, :hash, :video_id, :image_hash] }]).to_h
  end

  def creative_params
    params.permit(:idempotency_key, :text, media: [:kind, :hash, :video_id, :image_hash]).to_h
  end

  def ensure_feature
    head :not_found unless Current.account.feature_enabled?('meta_ads_criar')
  end

  def ensure_manage
    render json: { error: 'forbidden' }, status: :forbidden unless Pundit.policy!(pundit_user, ::Crm::MetaAdsConnection).update?
  end

  def load_connection
    @connection = ::Crm::MetaAdsConnection.active.find_by(account_id: Current.account.id)
    render json: { error: 'not_connected' }, status: :not_found if @connection&.ad_account_id.blank?
  end

  def render_care_error(error)
    return render json: { error: error.code }, status: :not_found if error.code == 'ad_not_found'

    body = { error: error.code, idempotency_key: error.attempt_key }.compact
    return render json: body, status: :conflict if error.code == 'in_progress'

    render json: body.merge(nothing_created: error.nothing_created), status: :unprocessable_entity
  end

  def audit_copy!(copied)
    audit!(COPIED_ACTION, 'source_ad_id' => params[:ad_id].to_s, 'ad_id' => copied[:ad_id], 'ad_name' => copied[:name],
                          'campaign_id' => copied[:campaign_id], 'new_creative' => copy_params[:creative].present?,
                          'budget' => copied[:budget].slice('kind', 'amount', 'currency'))
  end

  # A Meta já mudou quando isto roda: falha ao gravar vai para o rastreador de erros e a resposta continua dizendo a
  # verdade (como no Crm::MetaAdsCreationController).
  def audit!(action, changes)
    Audited.audit_class.create!(auditable: Current.account, user: Current.user, action: action, audited_changes: changes)
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: Current.account).capture_exception
  end
end
