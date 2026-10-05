class Api::V1::Accounts::CtwaTrackedLinksController < Api::V1::Accounts::BaseController
  # Parâmetros de URL que o marketing cola no anúncio da Meta (modo site, #1011). As chaves
  # {{...}} são macros da Meta, preenchidas por ela em cada clique.
  AD_URL_PARAMS = 'utm_source=meta&utm_medium=paid&utm_campaign={{campaign.name}}&utm_term={{adset.name}}' \
                  '&utm_content={{ad.name}}&utm_id={{campaign.id}}'.freeze

  before_action :fetch_tracked_link, only: [:update, :destroy]

  def index
    authorize ::Inbox, :campaigns?

    links = tracked_links.to_a
    @campaigns = Ctwa::TrackedLinkCampaigns.for_links(Current.account, links.select(&:website?), include_revenue: revenue_visible?)
    render json: { payload: links.map { |tracked_link| tracked_link_payload(tracked_link) } }
  end

  def create
    inbox = Current.account.inboxes.find(tracked_link_params[:inbox_id])
    authorize ::Campaign, :create?

    tracked_link = Ctwa::TrackedLink.create!(create_attributes(inbox))

    render json: { payload: tracked_link_payload(tracked_link) }, status: :created
  end

  def update
    authorize ::Campaign, :update?

    @tracked_link.update!(update_attributes)
    @campaigns = Ctwa::TrackedLinkCampaigns.for_links(Current.account, [@tracked_link].select(&:website?), include_revenue: revenue_visible?)
    render json: { payload: tracked_link_payload(@tracked_link) }
  end

  def destroy
    authorize ::Campaign, :destroy?

    @tracked_link.destroy!
    head :no_content
  end

  private

  def tracked_links
    Ctwa::TrackedLink.where(account_id: Current.account.id).order(id: :desc)
  end

  def fetch_tracked_link
    @tracked_link = Ctwa::TrackedLink.where(account_id: Current.account.id).find(params[:id])
  end

  def tracked_link_params
    source_params = params[:ctwa_tracked_link].presence || params
    source_params.permit(:name, :inbox_id, :prefilled_text, :usage, allowed_origins: [])
  end

  # `usage` só na criação; texto pré-preenchido só existe no QR/link direto — no modo site
  # o texto é da página (cotação + código).
  def create_attributes(inbox)
    usage = tracked_link_params[:usage].presence || 'direct'
    attributes = { account: Current.account, inbox: inbox, name: tracked_link_params[:name], usage: usage }
    attributes[:prefilled_text] = tracked_link_params[:prefilled_text] if usage == 'direct'
    attributes[:allowed_origins] = Array(tracked_link_params[:allowed_origins]) if tracked_link_params.key?(:allowed_origins)
    attributes
  end

  def update_attributes
    attributes = tracked_link_params.slice(:name).to_h
    attributes[:prefilled_text] = tracked_link_params[:prefilled_text] if !@tracked_link.website? && tracked_link_params.key?(:prefilled_text)
    attributes[:allowed_origins] = Array(tracked_link_params[:allowed_origins]) if tracked_link_params.key?(:allowed_origins)
    attributes
  end

  def tracked_link_payload(tracked_link)
    base_payload(tracked_link).merge(website_payload(tracked_link))
  end

  def base_payload(tracked_link)
    {
      id: tracked_link.id,
      name: tracked_link.name,
      code: tracked_link.code,
      usage: tracked_link.usage,
      prefilled_text: tracked_link.prefilled_text,
      clicks_count: tracked_link.clicks_count,
      conversations_count: tracked_link.conversations_count,
      inbox_id: tracked_link.inbox_id,
      wa_link: tracked_link.wa_link,
      short_url: short_url_for(tracked_link)
    }
  end

  def website_payload(tracked_link)
    return { allowed_origins: [], last_signal_at: nil, signal_url: nil, ad_url_params: nil, campaigns: [] } unless tracked_link.website?

    {
      allowed_origins: tracked_link.allowed_origins,
      last_signal_at: tracked_link.last_signal_at&.iso8601,
      signal_url: "#{short_url_for(tracked_link)}/clicks",
      ad_url_params: AD_URL_PARAMS,
      campaigns: (@campaigns || {}).fetch(tracked_link.id, [])
    }
  end

  # Valor de vendas por campanha é financeiro: só administrador vê (nunca por função).
  def revenue_visible?
    Current.account_user&.administrator? || false
  end

  def short_url_for(tracked_link)
    "#{ENV.fetch('FRONTEND_URL', '').to_s.chomp('/')}/l/#{tracked_link.code}"
  end
end
