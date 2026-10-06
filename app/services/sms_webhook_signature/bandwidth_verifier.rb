# frozen_string_literal: true

# Checks the HTTP Basic Auth credential Bandwidth sends with messaging callbacks (#1027).
#
# Bandwidth has no HMAC signature for messaging callbacks: the application (Dashboard > Applications >
# messaging application > callback authentication) sends a username/password with every callback.
#
# Credential source, first match wins:
#   1. channel provider_config['callback_username'] / ['callback_password']
#   2. ENV BANDWIDTH_CALLBACK_USERNAME / BANDWIDTH_CALLBACK_PASSWORD (one credential for every channel)
#
# The channel is the one the payload acts on (`to` of the first event), the same lookup as
# Webhooks::SmsEventsJob, so the credential checked always belongs to the channel that gets updated.
class SmsWebhookSignature::BandwidthVerifier
  Result = Struct.new(:status, :channel, keyword_init: true)

  def initialize(request:, event:)
    @request = request
    @event = event
  end

  def perform
    return result(:channel_not_found) if channel.blank?
    return result(:missing_credentials) if expected_username.blank? || expected_password.blank?
    return result(:missing_signature) unless ActionController::HttpAuthentication::Basic.has_basic_credentials?(request)

    result(valid_credentials? ? :valid : :invalid_signature)
  end

  private

  attr_reader :request, :event

  def result(status)
    Result.new(status: status, channel: channel)
  end

  def channel
    return @channel if defined?(@channel)

    number = event.is_a?(Hash) ? event['to'] : nil
    @channel = number.present? ? ::Channel::Sms.find_by(phone_number: number) : nil
  end

  def provider_config
    (channel.provider_config || {}).to_h
  end

  def expected_username
    provider_config['callback_username'].presence || ENV.fetch('BANDWIDTH_CALLBACK_USERNAME', nil).presence
  end

  def expected_password
    provider_config['callback_password'].presence || ENV.fetch('BANDWIDTH_CALLBACK_PASSWORD', nil).presence
  end

  def valid_credentials?
    username, password = ActionController::HttpAuthentication::Basic.user_name_and_password(request)
    # Both comparisons always run so the response time does not reveal which half was wrong.
    username_ok = ActiveSupport::SecurityUtils.secure_compare(username.to_s, expected_username)
    password_ok = ActiveSupport::SecurityUtils.secure_compare(password.to_s, expected_password)
    username_ok && password_ok
  end
end
