# Adds the campaign journey listeners to AsyncDispatcher without editing it (#1002, PRD §8.0-2).
#
# Two paths, so the result does not depend on initializer order:
# - prepended on AsyncDispatcher (config/initializers/campaign_journey.rb): every later
#   load_listeners subscribes ReplyMarkListener;
# - .ensure_subscribed! (to_prepare and after_initialize of the same initializer): when the
#   dispatcher already loaded its listeners before the prepend, the listener is added to it.
# Both are idempotent: the listener is never subscribed twice.
module CampaignJourney::AsyncDispatcherListeners
  def self.listener
    CampaignJourney::ReplyMarkListener.instance
  end

  def self.ensure_subscribed!(dispatcher = Rails.configuration.try(:dispatcher))
    async = dispatcher.try(:async_dispatcher)
    return false if async.nil? || subscribed?(async)

    async.subscribe(listener)
    true
  end

  # Wisper keeps a publisher's own listeners in local_registrations (private).
  def self.subscribed?(async)
    async.send(:local_registrations).any? { |registration| registration.try(:listener).equal?(listener) }
  end

  def listeners
    own = CampaignJourney::AsyncDispatcherListeners.listener
    current = super
    current.include?(own) ? current : current + [own]
  end

  # Same as BaseDispatcher#load_listeners, but skips the journey listener when ensure_subscribed!
  # already added it.
  def load_listeners
    own = CampaignJourney::AsyncDispatcherListeners.listener
    already = CampaignJourney::AsyncDispatcherListeners.subscribed?(self)
    listeners.each { |item| subscribe(item) unless already && item.equal?(own) }
  end
end
