# Instagram pelo login único (#2406, flags `anuncios_login_unico` e `instagram_login_unico`): liga o Instagram da
# Página escolhida com o mesmo "Entrar com o Facebook" dos Anúncios. Sem as duas flags, 404: nada aqui chama a Meta.
#
# POST meta_ads_connection/instagram → page_id: liga o Instagram da Página (Crm::MetaAds::LoginUnico::LigarInstagram)
#      e devolve a caixa.
#
# As mesmas réguas do MetaAdsPaginaController: `meta_ads_manage`, conexão ativa com conta de anúncios, e Instagram sem
# caixa cria uma (`inbox_manage`); com caixa, troca o login dela (`integration_manage`). Erros: 422 com o código do
# serviço (`missing_permissions`, `no_instagram`, `page_not_granted`, `reconnect`, `meta_unavailable`,
# `not_own_token`) ou `page_id_required`.
class Api::V1::Accounts::Crm::MetaAdsInstagramController < Api::V1::Accounts::Crm::BaseController
  before_action :ensure_feature
  before_action :ensure_manage
  before_action :load_connection

  def create
    page_id = params[:page_id].to_s
    return render_unprocessable('page_id_required') unless numeric_id?(page_id)
    # No modo parceiro o token é o da plataforma: nem a leitura da régua abaixo chama a Meta com ele.
    return render_unprocessable('not_own_token') unless @connection.own_token?
    return render json: { error: 'forbidden' }, status: :forbidden unless can_link?(page_id)

    inbox = service.call(page_id)
    render json: { inbox_id: inbox.id, name: inbox.name }
  rescue ::Crm::MetaAds::LoginUnico::LigarInstagram::Error => e
    render_unprocessable(e.code)
  rescue CustomExceptions::Inbox::LimitExceeded => e
    render_error_response(e)
  end

  private

  def ensure_feature
    enabled = %w[anuncios_login_unico instagram_login_unico].all? { |flag| Current.account.feature_enabled?(flag) }
    head :not_found unless enabled
  end

  def ensure_manage
    allowed = Pundit.policy!(pundit_user, ::Crm::MetaAdsConnection).update?
    render json: { error: 'forbidden' }, status: :forbidden unless allowed
  end

  def load_connection
    @connection = ::Crm::MetaAdsConnection.active.find_by(account_id: Current.account.id)
    render json: { error: 'not_connected' }, status: :not_found if @connection&.ad_account_id.blank?
  end

  def numeric_id?(value)
    value.present? && value.each_char.all? { |char| char.between?('0', '9') }
  end

  # Ler o Instagram da Página já é uma chamada à Meta: o erro dela sobe para o `create`, que responde 422.
  def can_link?(page_id)
    key = service.existing(page_id) ? 'integration_manage' : 'inbox_manage'
    Current.account_user&.permission_granted?(key)
  end

  def service
    @service ||= ::Crm::MetaAds::LoginUnico::LigarInstagram.new(@connection)
  end
end
