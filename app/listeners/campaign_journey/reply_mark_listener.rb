# Campaign mark on reply (#1002, PRD D14 and §8.3). Registered on AsyncDispatcher by
# config/initializers/campaign_journey.rb (AsyncDispatcher is not edited). Off with the journey
# (CAMPAIGN_JOURNEY_ENABLED).
class CampaignJourney::ReplyMarkListener < BaseListener
  def message_created(event)
    message, = extract_message_and_account(event)
    return unless message.incoming? && !message.private?
    return unless CampaignJourney::Config.enabled?

    CampaignJourney::ReplyMarkJob.perform_later(message.id)
  end
end
