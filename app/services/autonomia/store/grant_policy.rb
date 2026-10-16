# frozen_string_literal: true

require 'time'

class Autonomia::Store::GrantPolicy
  def self.allowed?(snapshot, subscription_id:, reservation_id:, now: Time.now.utc)
    return false unless snapshot.fetch('effectiveAccess') == 'granted'

    snapshot.fetch('grants').any? do |grant|
      grant.fetch('serviceSubscriptionId') == subscription_id && grant.fetch('reservationId') == reservation_id &&
        grant.fetch('status') == 'granted' &&
        (grant.fetch('effectiveUntil').nil? || Time.iso8601(grant.fetch('effectiveUntil')) > now)
    end
  end
end
