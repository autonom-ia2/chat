class Api::V1::Accounts::CtwaTrackedLinksController < Api::V1::Accounts::BaseController
  before_action :fetch_tracked_link, only: [:update, :destroy]

  def index
    authorize ::Inbox, :campaigns?

    links = tracked_links.to_a
    @campaigns = Ctwa::TrackedLinkCampaigns.for_links(Current.account, links.select(&:website?), account_user: Current.account_user)
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
    @campaigns = Ctwa::TrackedLinkCampaigns.for_links(Current.account, [@tracked_link].select(&:website?), account_user: Current.account_user)
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

  def create_attributes(inbox)
    Ctwa::TrackedLinkAttributes.for_create(account: Current.account, inbox: inbox, params: tracked_link_params)
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
      short_url: Ctwa::TrackedLinkPayload.short_url(tracked_link)
    }
  end

  def website_payload(tracked_link)
    unless tracked_link.website?
      return { allowed_origins: [], last_signal_at: nil, signals_blocked: false, signal_url: nil, kit_url: nil, ad_url_params: nil, campaigns: [] }
    end

    Ctwa::TrackedLinkPayload.website(tracked_link).merge(campaigns: (@campaigns || {}).fetch(tracked_link.id, []))
  end
end
