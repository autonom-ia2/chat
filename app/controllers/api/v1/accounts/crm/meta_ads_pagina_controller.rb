# Login único (#2338, flag `anuncios_login_unico`): a Página vem do mesmo "Entrar com o Facebook" dos Anúncios. Sem a
# flag, 404: nada aqui chama a Meta.
#
# GET  meta_ads_connection/paginas → Páginas que a pessoa marcou na janela da Meta, com o Instagram ligado (só para
#      mostrar), se já têm caixa aqui e as permissões que ela recusou (Crm::MetaAds::LoginUnico::Paginas).
# POST meta_ads_connection/pagina  → page_id: liga a Página (Crm::MetaAds::LoginUnico::LigarPagina) e devolve a caixa.
#
# Os dois pedem `meta_ads_manage` (a conexão guiada é dela). Ligar ainda segue a régua das caixas: Página sem caixa
# cria uma (`inbox_manage`); com caixa, troca o token dela (`integration_manage`), como o CallbacksController.
# Sem conexão ativa com conta de anúncios: 404 not_connected. A Meta fora: 422 meta_unavailable. O acesso do login
# venceu: 422 reconnect. Página com caixa e login sem o que a caixa usa: 422 missing_permissions, sem trocar o
# token. `page_id` é o id numérico da Página; outra coisa é 422 page_id_required.
class Api::V1::Accounts::Crm::MetaAdsPaginaController < Api::V1::Accounts::Crm::BaseController
  before_action :ensure_feature
  before_action :ensure_manage
  before_action :load_connection

  def index
    data = ::Crm::MetaAds::LoginUnico::Paginas.new(@connection).call
    return render_unprocessable('meta_unavailable') if data.nil?

    render json: data
  end

  def create
    page_id = params[:page_id].to_s
    return render_unprocessable('page_id_required') unless numeric_id?(page_id)
    return render json: { error: 'forbidden' }, status: :forbidden unless can_link?(page_id)

    inbox = service.call(page_id)
    render json: { inbox_id: inbox.id, name: inbox.name }
  rescue ::Crm::MetaAds::LoginUnico::LigarPagina::Error => e
    render_unprocessable(e.code)
  rescue CustomExceptions::Inbox::LimitExceeded => e
    render_error_response(e)
  end

  private

  def ensure_feature
    head :not_found unless Current.account.feature_enabled?('anuncios_login_unico')
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

  def can_link?(page_id)
    key = service.existing(page_id) ? 'integration_manage' : 'inbox_manage'
    Current.account_user&.permission_granted?(key)
  end

  def service
    @service ||= ::Crm::MetaAds::LoginUnico::LigarPagina.new(@connection)
  end
end
