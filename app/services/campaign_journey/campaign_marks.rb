# Campaign mark in the CRM (#1002, PRD D14, §6.7 and §8.3): a campaign becomes an origin touch
# on the conversation through the same mechanism as Links and QR codes
# (Ctwa::CampaignBuilder.attribute!). The first touch stays the origin; a campaign that arrives
# later is appended to campaign_touches (K7). Idempotent per conversation + campaign: the
# builder dedups by source_id.
module CampaignJourney::CampaignMarks
  module_function

  WHATSAPP_SOURCE = 'campaign_whatsapp'.freeze
  EMAIL_SOURCE = 'campaign_email'.freeze
  # #993 (PRD §6.8, M5): who talks through a live chat campaign of the website.
  LIVE_CHAT_SOURCE = 'campaign_live_chat'.freeze
  SOURCES = [WHATSAPP_SOURCE, EMAIL_SOURCE, LIVE_CHAT_SOURCE].freeze
  LIVE_CHAT_KIND = [LIVE_CHAT_SOURCE, 'live_chat', :title].freeze

  # campaign class => [source_type, <type> of the "campaign:<type>:<id>" source id, name attribute]
  KINDS = {
    'Campaign' => [WHATSAPP_SOURCE, 'whatsapp', :title],
    'WhatsappApiCampaign' => [WHATSAPP_SOURCE, 'whatsapp_api', :title],
    'EmailCampaign' => [EMAIL_SOURCE, 'email', :name]
  }.freeze

  def mark!(conversation, campaign)
    source_type, type, name_attribute = kind_for(campaign)
    source_id = "campaign:#{type}:#{campaign.id}"
    return false if marked?(conversation, source_id)

    Ctwa::CampaignBuilder.attribute!(
      conversation,
      source_id: source_id, source_type: source_type, headline: campaign.public_send(name_attribute)
    )
  end

  # Chatwoot's ongoing campaigns are the live chat messages of the website (#993).
  def kind_for(campaign)
    return LIVE_CHAT_KIND if campaign.is_a?(Campaign) && campaign.ongoing?

    KINDS.fetch(campaign.class.name)
  end

  # Cheap in-memory check so repeated replies never take the row lock of the builder.
  def marked?(conversation, source_id)
    Array(conversation.additional_attributes.to_h['campaign_source_ids']).include?(source_id)
  end
end
