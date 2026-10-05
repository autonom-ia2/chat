# Daily refresh of Instagram (Business Login) tokens that are about to expire.
#
# Instagram::RefreshOauthTokenService only refreshes lazily, when a message needs the token.
# An inbox without traffic during the last days of the 60-day window would silently expire,
# so this job asks for the token of every channel inside the refresh window. When Meta
# refuses and the token is close to expiring, the inbox is flagged for reconnection, which
# also emails the account admins.
class Instagram::RefreshTokensJob < ApplicationJob
  queue_as :scheduled_jobs

  REFRESH_WINDOW = 10.days
  REAUTHORIZATION_WINDOW = 2.days
  MINIMUM_TOKEN_AGE = 24.hours

  def perform
    Channel::Instagram.where(expires_at: Time.current..REFRESH_WINDOW.from_now).find_each do |channel|
      refresh(channel)
    end
  end

  private

  def refresh(channel)
    previous_expiry = channel.expires_at
    channel.access_token
    return clear_reauthorization(channel) if channel.reload.expires_at > previous_expiry

    flag_for_reauthorization(channel)
  rescue StandardError => e
    Rails.logger.error("[#{self.class.name}] channel #{channel.id}: #{e.class.name}")
  end

  def clear_reauthorization(channel)
    channel.reauthorized! if channel.reauthorization_required?
  end

  # Meta only refreshes tokens at least 24h old (RefreshOauthTokenService uses updated_at for that),
  # so an unchanged expiry on a younger record is not a refresh failure.
  def flag_for_reauthorization(channel)
    return if channel.updated_at > MINIMUM_TOKEN_AGE.ago
    return if channel.expires_at > REAUTHORIZATION_WINDOW.from_now || channel.reauthorization_required?

    Rails.logger.warn("[#{self.class.name}] channel #{channel.id}: token refresh failed, expires at #{channel.expires_at}")
    channel.prompt_reauthorization!
  end
end
