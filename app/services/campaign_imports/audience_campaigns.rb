# Campaigns that used an audience (#993, PRD §6.6 side panel, F1): every campaign linked to it by
# campaign_audience_links (journey campaigns and old campaigns linked by the backfill), newest
# first, as { type, id, title, channel, status }. Channel follows the journey list keys.
module CampaignImports::AudienceCampaigns
  LIMIT = 50

  module_function

  def for(campaign_import)
    campaign_import.campaign_audience_links.includes(:campaign).order(created_at: :desc).limit(LIMIT)
                   .filter_map { |link| link.campaign && entry(link.campaign) }
  end

  def entry(campaign)
    case campaign
    when EmailCampaign
      { type: 'EmailCampaign', id: campaign.id, title: campaign.name, channel: 'email', status: campaign.status }
    when WhatsappApiCampaign
      { type: 'WhatsappApiCampaign', id: campaign.id, title: campaign.title, channel: 'whatsapp_api', status: campaign.status }
    else
      { type: campaign.class.name, id: campaign.id, title: campaign.title, channel: 'whatsapp_official',
        status: campaign.try(:campaign_status) }
    end
  end
end
