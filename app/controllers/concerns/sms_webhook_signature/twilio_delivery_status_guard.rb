# frozen_string_literal: true

# Prepended into Twilio::DeliveryStatusController (StatusCallback) by config/initializers/sms_webhook_signature.rb.
module SmsWebhookSignature::TwilioDeliveryStatusGuard
  include SmsWebhookSignature::Gate

  def create
    passed = sms_webhook_signature_pass?(provider: 'twilio', endpoint: 'delivery_status') do
      SmsWebhookSignature::TwilioVerifier.new(request: request, number_param: 'From').perform
    end
    super if passed
  end
end
