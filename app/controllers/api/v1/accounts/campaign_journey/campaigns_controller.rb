# Campaign journey: creates a campaign that sends to a saved audience. Channels:
#   whatsapp_cloud — WhatsApp Oficial (#1005, docs/campaigns/publicos/api-1005.md);
#   sms            — SMS, Twilio SMS or Bandwidth (#1004, docs/campaigns/publicos/api-1004.md).
# CAMPAIGN_JOURNEY_ENABLED off → 404; campaign_manage required (CampaignPolicy#create?), otherwise 401.
class Api::V1::Accounts::CampaignJourney::CampaignsController < Api::V1::Accounts::BaseController
  before_action :ensure_campaign_journey_enabled
  before_action :check_authorization

  def create
    campaign_import = Current.account.campaign_imports.find(params.require(:campaign_import_id))
    channel = params[:channel].to_s
    campaign = creator_for(channel).new(
      account: Current.account, campaign_import: campaign_import, channel: channel, attributes: campaign_params
    ).perform
    render json: campaign_payload(campaign, channel)
  rescue ::CampaignJourney::AudienceCampaignCreator::Error => e
    render json: { error: e.message, code: e.code, details: e.details }.compact, status: :unprocessable_entity
  end

  private

  # Any channel other than sms keeps the #1005 behaviour (whatsapp_cloud_required).
  def creator_for(channel)
    channel == ::CampaignJourney::SmsCampaignCreator::CHANNEL ? ::CampaignJourney::SmsCampaignCreator : ::CampaignJourney::WhatsappCampaignCreator
  end

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

  def campaign_payload(campaign, channel)
    link = CampaignAudienceLink.for_campaign(campaign)
    sms = channel == ::CampaignJourney::SmsCampaignCreator::CHANNEL
    payload = {
      id: campaign.id, display_id: campaign.display_id, title: campaign.title,
      channel: sms ? channel : ::CampaignJourney::WhatsappCampaignCreator::CHANNEL, scheduled_at: campaign.scheduled_at,
      recipients_count: ::CampaignJourney::AudienceContacts.contacts_for(link, channel: sms ? :sms : :whatsapp).count
    }
    sms ? payload.merge(inbox_id: campaign.inbox_id, message_stats: ::CampaignJourney::SmsSegments.count(campaign.message)) : payload
  end
end
