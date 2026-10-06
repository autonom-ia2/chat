# frozen_string_literal: true

# Decides what happens to an SMS provider callback after its origin was checked (#1027).
#
# SMS_WEBHOOK_SIGNATURE_MODE
#   off     - no check at all (behaviour before #1027)
#   log     - check and log the outcome, always process (default, rollout phase)
#   enforce - a forged callback is answered 401 and never processed
#
# SMS_WEBHOOK_UNVERIFIABLE_POLICY (only read in enforce mode)
#   allow  - a callback we cannot check (no channel, no credential to check against) is processed (default)
#   reject - such a callback is answered 401 as well
class SmsWebhookSignature::Policy
  MODES = %w[off log enforce].freeze
  DEFAULT_MODE = 'log'
  UNVERIFIABLE_POLICIES = %w[allow reject].freeze
  DEFAULT_UNVERIFIABLE_POLICY = 'allow'

  FORGED_RESULTS = %i[invalid_signature missing_signature].freeze
  UNVERIFIABLE_RESULTS = %i[channel_not_found missing_credentials].freeze

  def self.mode
    value = ENV.fetch('SMS_WEBHOOK_SIGNATURE_MODE', DEFAULT_MODE).to_s.strip.downcase
    MODES.include?(value) ? value : DEFAULT_MODE
  end

  def self.unverifiable_policy
    value = ENV.fetch('SMS_WEBHOOK_UNVERIFIABLE_POLICY', DEFAULT_UNVERIFIABLE_POLICY).to_s.strip.downcase
    UNVERIFIABLE_POLICIES.include?(value) ? value : DEFAULT_UNVERIFIABLE_POLICY
  end

  def self.reject?(mode, result)
    return false unless mode == 'enforce'
    return true if FORGED_RESULTS.include?(result)

    UNVERIFIABLE_RESULTS.include?(result) && unverifiable_policy == 'reject'
  end
end
