# Campaign journey (#1005): creates a WhatsApp Oficial campaign that sends to a saved audience.
# Contract in docs/campaigns/publicos/api-1005.md. CAMPAIGN_JOURNEY_ENABLED off → 404;
# campaign_manage required (CampaignPolicy#create?), otherwise 401.
class Api::V1::Accounts::CampaignJourney::CampaignsController < Api::V1::Accounts::BaseController
  before_action :ensure_campaign_journey_enabled
  before_action :check_authorization

  def create
    campaign_import = Current.account.campaign_imports.campaign_flows.find(params.require(:campaign_import_id))
    campaign = ::CampaignJourney::WhatsappCampaignCreator.new(
      account: Current.account, campaign_import: campaign_import, channel: params[:channel], attributes: campaign_params
    ).perform
    render json: campaign_payload(campaign)
  rescue ::CampaignJourney::WhatsappCampaignCreator::Error => e
    render json: { error: e.message, code: e.code, details: e.details }.compact, status: :unprocessable_entity
  end

  private

  def check_authorization
    authorize(Campaign, :create?)
  end

  def ensure_campaign_journey_enabled
    return if ::CampaignJourney::Config.enabled?

    render json: { error: 'campaign_journey.disabled', code: 'campaign_journey_disabled' }, status: :not_found
  end

  # template_params: same shape Api::V1::Accounts::CampaignsController accepts.
  def campaign_params
    params.require(:campaign).permit(
      :title, :inbox_id, :scheduled_at, :message, template_params: {}, variable_bindings: {}, variable_defaults: {}
    ).to_h
  end

  def campaign_payload(campaign)
    link = CampaignAudienceLink.for_campaign(campaign)
    {
      id: campaign.id, display_id: campaign.display_id, title: campaign.title,
      channel: ::CampaignJourney::WhatsappCampaignCreator::CHANNEL, scheduled_at: campaign.scheduled_at,
      recipients_count: ::CampaignJourney::AudienceContacts.contacts_for(link, channel: :whatsapp).count
    }
  end
end
