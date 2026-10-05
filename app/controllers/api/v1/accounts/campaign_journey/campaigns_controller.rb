# Campaign journey: creates a campaign that sends to a saved audience. Channels:
#   whatsapp_cloud — WhatsApp Oficial (#1005, docs/campaigns/publicos/api-1005.md);
#   whatsapp_api   — WhatsApp API (#999, docs/campaigns/publicos/api-999.md);
#   email          — e-mail draft for the existing builder flow (#999, api-999.md).
# CAMPAIGN_JOURNEY_ENABLED off → 404; campaign_manage required (CampaignPolicy#create?), otherwise 401.
class Api::V1::Accounts::CampaignJourney::CampaignsController < Api::V1::Accounts::BaseController
  CHANNELS = %w[whatsapp_cloud whatsapp_api email].freeze

  before_action :ensure_campaign_journey_enabled
  before_action :check_authorization

  def create
    campaign_import = Current.account.campaign_imports.find(params.require(:campaign_import_id))
    render json: create_for(params[:channel].to_s, campaign_import)
  rescue ::CampaignJourney::WhatsappCampaignCreator::Error, ::CampaignJourney::CreatorError => e
    render json: { error: e.message, code: e.code, details: e.details }.compact, status: :unprocessable_entity
  end

  private

  def create_for(channel, campaign_import)
    case channel
    when ::CampaignJourney::WhatsappApiCampaignCreator::CHANNEL then create_whatsapp_api(campaign_import)
    when ::CampaignJourney::EmailCampaignCreator::CHANNEL then create_email(campaign_import)
    when ::CampaignJourney::WhatsappCampaignCreator::CHANNEL then create_whatsapp_cloud(campaign_import)
    else raise ::CampaignJourney::CreatorError.new('unsupported_channel', "Channel must be one of: #{CHANNELS.join(', ')}")
    end
  end

  def create_whatsapp_cloud(campaign_import)
    campaign = ::CampaignJourney::WhatsappCampaignCreator.new(
      account: Current.account, campaign_import: campaign_import, channel: params[:channel], attributes: whatsapp_cloud_params
    ).perform
    link = CampaignAudienceLink.for_campaign(campaign)
    {
      id: campaign.id, display_id: campaign.display_id, title: campaign.title,
      channel: ::CampaignJourney::WhatsappCampaignCreator::CHANNEL, scheduled_at: campaign.scheduled_at,
      recipients_count: ::CampaignJourney::AudienceContacts.contacts_for(link, channel: :whatsapp).count
    }
  end

  def create_whatsapp_api(campaign_import)
    campaign = ::CampaignJourney::WhatsappApiCampaignCreator.new(
      account: Current.account, user: Current.user, campaign_import: campaign_import, params: params.require(:campaign)
    ).perform
    link = CampaignAudienceLink.for_campaign(campaign)
    {
      id: campaign.id, title: campaign.title, channel: ::CampaignJourney::WhatsappApiCampaignCreator::CHANNEL,
      scheduled_at: campaign.scheduled_at, inbox_id: campaign.inbox_id,
      recipients_count: ::CampaignJourney::AudienceContacts.contacts_for(link, channel: :whatsapp).count
    }
  end

  def create_email(campaign_import)
    campaign = ::CampaignJourney::EmailCampaignCreator.new(
      account: Current.account, campaign_import: campaign_import, attributes: email_params
    ).perform.reload
    {
      id: campaign.id, title: campaign.name, channel: ::CampaignJourney::EmailCampaignCreator::CHANNEL, status: campaign.status,
      delivery_mode: campaign.delivery_mode, reply_to_inbox_id: campaign.reply_to_inbox_id,
      recipients_count: campaign.email_campaign_recipients.pending.count,
      suppressed_count: campaign.email_campaign_recipients.suppressed.count
    }
  end

  def check_authorization
    authorize(Campaign, :create?)
  end

  def ensure_campaign_journey_enabled
    return if ::CampaignJourney::Config.enabled?

    render json: { error: 'campaign_journey.disabled', code: 'campaign_journey_disabled' }, status: :not_found
  end

  # template_params: same shape Api::V1::Accounts::CampaignsController accepts.
  def whatsapp_cloud_params
    params.require(:campaign).permit(
      :title, :inbox_id, :scheduled_at, :message, template_params: {}, variable_bindings: {}, variable_defaults: {}
    ).to_h
  end

  def email_params
    params.require(:campaign).permit(
      :title, :delivery_mode, :sender_identity_id, :sender_inbox_id, :from_name, :from_email, :reply_to_inbox_id, :subject, :preheader
    ).to_h
  end
end
