json.payload do
  json.partial! 'campaign', campaign: @campaign
  json.send_readiness EmailCampaigns::Presentation::SendReadiness.new(@campaign).call
  # #1002 (K4): #CODE for the "talk on WhatsApp" button; the reply then gets the campaign mark.
  json.whatsapp_reply_code CampaignJourney::ReplyCodes.code_for!(@campaign) if CampaignJourney::Config.enabled?
end
