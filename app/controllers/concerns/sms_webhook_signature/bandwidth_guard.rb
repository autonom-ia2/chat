# frozen_string_literal: true

# Prepended into Webhooks::SmsController (Bandwidth) by config/initializers/sms_webhook_signature.rb.
module SmsWebhookSignature::BandwidthGuard
  include SmsWebhookSignature::Gate

  def process_payload
    passed = sms_webhook_signature_pass?(provider: 'bandwidth', endpoint: 'sms') do
      SmsWebhookSignature::BandwidthVerifier.new(request: request, event: sms_webhook_signature_event).perform
    end
    super if passed
  end

  private

  def sms_webhook_signature_event
    event = params['_json']&.first
    event.respond_to?(:to_unsafe_h) ? event.to_unsafe_h : event
  end
end
