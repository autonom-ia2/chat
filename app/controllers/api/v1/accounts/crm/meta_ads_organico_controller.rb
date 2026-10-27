# Anúncios da Meta › Seus posts (#2199): GET meta_ads_connection/organico?days=7|30|90. Atrás da flag da conta
# `meta_ads_organico` (404 desligada). Quem vê os Anúncios da Meta vê (administrador ou `meta_ads_view`, policy
# Crm::MetaAdsConnection :show?); as conversas contadas são só as que a pessoa vê. Período fora de 7, 30 e 90: 422.
# Meta fora do ar: 503 `meta_unavailable` (a tela mostra "Tentar de novo"). Números em Crm::MetaAds::Organico::Tela.
class Api::V1::Accounts::Crm::MetaAdsOrganicoController < Api::V1::Accounts::Crm::BaseController
  before_action :ensure_organico_enabled
  before_action :ensure_allowed

  rescue_from Crm::MetaAds::Organico::Indisponivel do
    render json: { error: 'meta_unavailable' }, status: :service_unavailable
  end

  def show
    days = params[:days].to_i
    return render_unprocessable('invalid_period') unless Crm::MetaAds::Organico::Periodo::DIAS.include?(days)

    render json: Crm::MetaAds::Organico::Tela.new(account: Current.account, days: days, viewer: pundit_user).perform
  end

  private

  def ensure_organico_enabled
    render json: { error: 'not_found' }, status: :not_found unless Current.account.feature_enabled?('meta_ads_organico')
  end

  def ensure_allowed
    return if Pundit.policy!(pundit_user, ::Crm::MetaAdsConnection).show?

    render json: { error: 'forbidden' }, status: :forbidden
  end
end
