# frozen_string_literal: true

# #1027: origin check of the SMS provider callbacks inherited from Chatwoot, without editing the
# upstream controllers. Mode and rollout: docs/runbooks/sms-webhook-signature.md.
Rails.application.config.to_prepare do
  prepend_once = lambda do |klass, mod|
    klass.prepend(mod) unless klass.ancestors.include?(mod)
  end

  prepend_once.call(Twilio::CallbackController, SmsWebhookSignature::TwilioCallbackGuard)
  prepend_once.call(Twilio::DeliveryStatusController, SmsWebhookSignature::TwilioDeliveryStatusGuard)
  prepend_once.call(Webhooks::SmsController, SmsWebhookSignature::BandwidthGuard)
end
