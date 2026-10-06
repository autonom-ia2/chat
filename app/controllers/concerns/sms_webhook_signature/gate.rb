# frozen_string_literal: true

# Shared by the guards prepended into the upstream SMS callback controllers (#1027).
# Runs the verifier for the current mode, logs a sanitized line and tells the guard whether to go on.
# The log carries provider, endpoint, mode, result, channel id and action only: never phone numbers,
# SIDs, signatures, credentials or message content.
module SmsWebhookSignature::Gate
  LOG_TAG = '[SmsWebhookSignature]'

  private

  # Returns true when the callback must be processed, false when it was rejected (401 already rendered).
  def sms_webhook_signature_pass?(provider:, endpoint:)
    mode = SmsWebhookSignature::Policy.mode
    return true if mode == 'off'

    verification = yield
    rejected = SmsWebhookSignature::Policy.reject?(mode, verification.status)
    sms_webhook_signature_log(provider, endpoint, mode, verification, rejected)
    return true unless rejected

    sms_webhook_signature_reject(provider)
    false
  end

  def sms_webhook_signature_reject(provider)
    response.headers['WWW-Authenticate'] = 'Basic realm="Bandwidth callbacks"' if provider == 'bandwidth'
    head :unauthorized
  end

  def sms_webhook_signature_log(provider, endpoint, mode, verification, rejected)
    line = "#{LOG_TAG} provider=#{provider} endpoint=#{endpoint} mode=#{mode} " \
           "result=#{verification.status} channel_id=#{verification.channel&.id || 'none'} " \
           "action=#{rejected ? 'rejected' : 'processed'}"
    verification.status == :valid ? Rails.logger.info(line) : Rails.logger.warn(line)
  end
end
