json.payload do
  json.summary @summary
  json.campaigns @campaigns
  json.campaign_options @campaign_options
  json.applied_filters @applied_filters
  json.protection @protection
  json.preflight @preflight
  json.meta @meta
end
