# frozen_string_literal: true

# Prepended into Twilio::CallbackController (inbound SMS/WhatsApp) by config/initializers/sms_webhook_signature.rb.
module SmsWebhookSignature::TwilioCallbackGuard
  include SmsWebhookSignature::Gate

  def create
    passed = sms_webhook_signature_pass?(provider: 'twilio', endpoint: 'callback') do
      SmsWebhookSignature::TwilioVerifier.new(request: request, number_param: 'To').perform
    end
    super if passed
  end
end
