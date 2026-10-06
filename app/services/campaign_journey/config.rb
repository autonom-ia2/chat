# CAMPAIGN_JOURNEY_ENABLED (PRD §8.0-6): the new campaign journey. Off → its endpoints answer
# 404 and the dashboard keeps the old campaign screens. Same ENV the dashboard reads (#993).
class CampaignJourney::Config
  def self.enabled?
    ActiveModel::Type::Boolean.new.cast(ENV.fetch('CAMPAIGN_JOURNEY_ENABLED', false))
  end
end
