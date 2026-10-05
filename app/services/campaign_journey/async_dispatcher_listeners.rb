# Adds the campaign journey listeners to AsyncDispatcher without editing it (#1002, PRD §8.0-2).
# Prepended by config/initializers/campaign_journey.rb, which runs before event_handlers.rb
# loads the listeners (to_prepare blocks run in initializer file order).
module CampaignJourney::AsyncDispatcherListeners
  def listeners
    super + [CampaignJourney::ReplyMarkListener.instance]
  end
end
