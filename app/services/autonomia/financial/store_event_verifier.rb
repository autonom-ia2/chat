# frozen_string_literal: true

require 'openssl'
require 'json'
require 'active_support/security_utils'

class Autonomia::Financial::StoreEventVerifier
  MAX_BODY_BYTES = 128 * 1024
  MAX_CLOCK_SKEW = 300

  def initialize(configuration:, secret: ENV.fetch('FINANCIAL_STORE_WEBHOOK_SECRET', ''))
    unless secret.is_a?(String) && secret.bytesize >= 32 && [configuration.api_key, configuration.assertion_secret].none?(secret)
      raise Autonomia::Financial::StoreClientError.new('STORE_NOT_CONFIGURED', status: 503)
    end

    @configuration = configuration
    @secret = secret
  end

  def verify!(body:, headers:, now: Time.now.to_i)
    raise Autonomia::Financial::StoreClientError.new('EVENT_TOO_LARGE', status: 413) if body.bytesize > MAX_BODY_BYTES

    verify_signature!(body, headers, now)
    event = JSON.parse(body)
    Autonomia::Financial::StoreCheckoutContract.validate_event!(event)
    raise Autonomia::Financial::StoreClientError.new('INVALID_EVENT', status: 422) if event.fetch('accessVersion').length > 30

    unless event.fetch('eventId') == headers['X-Store-Event-Id'].to_s && event.fetch('namespace') == @configuration.namespace
      raise Autonomia::Financial::StoreClientError.new('FORBIDDEN', status: 403)
    end

    event
  rescue JSON::ParserError, Autonomia::Financial::StoreContractError
    raise Autonomia::Financial::StoreClientError.new('INVALID_EVENT', status: 422)
  end

  private

  def verify_signature!(body, headers, now)
    timestamp = headers['X-Store-Timestamp'].to_s
    event_id = headers['X-Store-Event-Id'].to_s
    received = headers['X-Store-Signature'].to_s
    valid_headers = fresh_timestamp?(timestamp, now) && event_id.match?(/\A[0-9a-fA-F-]{36}\z/) && received.match?(/\Av1=[0-9a-f]{64}\z/)
    expected = OpenSSL::HMAC.hexdigest('SHA256', @secret, "#{timestamp}.#{event_id}.#{body}")
    return if valid_headers && ActiveSupport::SecurityUtils.secure_compare(expected, received.delete_prefix('v1='))

    raise Autonomia::Financial::StoreClientError.new('INVALID_SIGNATURE', status: 401)
  end

  def fresh_timestamp?(timestamp, now)
    timestamp.match?(/\A\d{1,12}\z/) && (timestamp.to_i - now).abs <= MAX_CLOCK_SKEW
  end
end
