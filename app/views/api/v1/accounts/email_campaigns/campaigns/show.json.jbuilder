json.payload do
  json.partial! 'campaign', campaign: @campaign
  json.send_readiness EmailCampaigns::Presentation::SendReadiness.new(@campaign).call
end
