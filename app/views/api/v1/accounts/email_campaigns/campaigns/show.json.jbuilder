json.payload do
  json.partial! 'campaign', campaign: @campaign
  json.send_readiness EmailCampaigns::Presentation::SendReadiness.new(@campaign).call
  # #999: only on the single campaign (one query each), so the list keeps its query budget.
  json.effective_reply_to EmailCampaigns::ReplyTo.for(@campaign)
  json.audience_id CampaignAudienceLink.for_campaign(@campaign)&.campaign_import_id
end
