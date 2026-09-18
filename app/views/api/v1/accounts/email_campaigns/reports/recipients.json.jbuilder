json.payload do
  json.campaign_id @campaign.id
  json.recipients @recipients
  json.meta @meta
end
