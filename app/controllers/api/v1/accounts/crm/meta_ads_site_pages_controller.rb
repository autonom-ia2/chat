# Anúncios › Destino (#2338): a página do site é ligada ali mesmo, sem ir a Links e QR codes. Por baixo é o mesmo link
# de site de Links e QR codes (Ctwa::TrackedLink, usage 'website').
#
# GET  meta_ads_connection/site_pages → páginas de site da conta: nome, caixa, código e sites permitidos. Sem
#      cliques, conversas nem valores (Ctwa::TrackedLinkCampaigns segue atrás de campaign_view em Links e QR codes).
#      Administrador ou `meta_ads_view`.
# POST meta_ads_connection/site_pages → { name, inbox_id, allowed_origins } → a página nova, sempre link de site.
#      Administrador ou `meta_ads_manage`. Editar e apagar continuam em Links e QR codes (campaign_manage).
#
# Sem a flag `meta_ads_hub`: 404.
class Api::V1::Accounts::Crm::MetaAdsSitePagesController < Api::V1::Accounts::Crm::BaseController
  before_action :ensure_feature
  before_action :ensure_view
  before_action :ensure_manage, only: [:create]

  def index
    pages = Ctwa::TrackedLink.where(account_id: Current.account.id, usage: 'website').order(id: :desc)
    render json: { payload: pages.map { |page| page_payload(page) } }
  end

  def create
    inbox = Current.account.inboxes.find(page_params[:inbox_id])
    page = Ctwa::TrackedLink.create!(page_attributes(inbox))
    render json: { payload: page_payload(page) }, status: :created
  end

  private

  def ensure_feature
    head :not_found unless Current.account.feature_enabled?('meta_ads_hub')
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

  def page_params
    params.permit(:name, :inbox_id, allowed_origins: [])
  end

  # Sempre página do site, qualquer que seja o `usage` pedido.
  def page_attributes(inbox)
    Ctwa::TrackedLinkAttributes.for_create(account: Current.account, inbox: inbox, params: page_params.merge(usage: 'website'))
  end

  def page_payload(page)
    { id: page.id, name: page.name, code: page.code, usage: page.usage, inbox_id: page.inbox_id }
      .merge(Ctwa::TrackedLinkPayload.website(page))
  end
end
