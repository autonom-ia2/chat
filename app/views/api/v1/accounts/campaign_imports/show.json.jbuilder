json.payload do
  json.partial! 'api/v1/models/campaign_import', formats: [:json], resource: @campaign_import
  # #993 (PRD B8): who does not receive, per channel, once the rows are validated.
  if @campaign_import.audience? && CampaignImports::AudienceReachability::STATUSES.include?(@campaign_import.status)
    json.reachability CampaignImports::AudienceReachability.new(@campaign_import).perform
  end
end
