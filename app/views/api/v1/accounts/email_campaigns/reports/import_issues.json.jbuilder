json.payload do
  json.campaign_id @campaign.id
  json.issues @issues
  json.meta @meta
  json.import_summary @import_summary
  json.preflight @preflight
end
