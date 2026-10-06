# frozen_string_literal: true

# Checks X-Twilio-Signature of a Twilio messaging callback with the official twilio-ruby validator (#1027).
#
# The channel is resolved exactly like the service the callback feeds: by MessagingServiceSid, then by
# AccountSid plus our number (`To` for inbound messages, `From` for delivery status).
#
# Twilio signs the URL it called. Behind the load balancer, request.original_url already honours
# X-Forwarded-Proto/X-Forwarded-Host (Rack); FRONTEND_URL + path is accepted as well because it is the
# exact base Chatwoot hands Twilio in `status_callback`. The validator itself tries the URL with and
# without the default port.
#
# A channel authenticated by API key keeps the API key secret in `auth_token`; Twilio signs with the
# account Auth Token, so such a channel cannot be checked and is reported as missing_credentials.
class SmsWebhookSignature::TwilioVerifier
  SIGNATURE_HEADER = 'X-Twilio-Signature'

  Result = Struct.new(:status, :channel, keyword_init: true)

  def initialize(request:, number_param:)
    @request = request
    @number_param = number_param
  end

  def perform
    return result(:channel_not_found) if channel.blank?
    return result(:missing_credentials) if channel.api_key_sid.present? || channel.auth_token.blank?
    return result(:missing_signature) if signature.blank?

    result(valid_signature? ? :valid : :invalid_signature)
  end

  private

  attr_reader :request, :number_param

  def result(status)
    Result.new(status: status, channel: channel)
  end

  def params
    @params ||= request.request_parameters.to_h
  end

  def signature
    request.headers[SIGNATURE_HEADER]
  end

  def channel
    return @channel if defined?(@channel)

    @channel = find_channel
  end

  def find_channel
    found = ::Channel::TwilioSms.find_by(messaging_service_sid: params['MessagingServiceSid']) if params['MessagingServiceSid'].present?
    return found if found.present?
    return if params['AccountSid'].blank? || params[number_param].blank?

    ::Channel::TwilioSms.find_by(account_sid: params['AccountSid'], phone_number: params[number_param])
  end

  def valid_signature?
    validator = ::Twilio::Security::RequestValidator.new(channel.auth_token)
    candidate_urls.any? { |url| validator.validate(url, params, signature) }
  end

  def candidate_urls
    [request.original_url, frontend_url].compact_blank.uniq
  end

  def frontend_url
    base = ENV.fetch('FRONTEND_URL', '').to_s.strip.delete_suffix('/')
    return if base.blank?

    "#{base}#{request.fullpath}"
  end
end
