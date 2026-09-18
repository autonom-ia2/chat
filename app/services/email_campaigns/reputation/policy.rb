require 'bigdecimal'

# Ratios, not percentages. The only calculator for the local seven-day SES cohort.
class EmailCampaigns::Reputation::Policy
  VERSION = 'local-ses-v1'.freeze
  WINDOW_SECONDS = 7 * 24 * 60 * 60
  attr_reader :mode, :version, :settings

  def initialize(env = ENV)
    @mode = env.fetch('EMAIL_REPUTATION_MODE', 'shadow')
    @version = env.fetch('EMAIL_REPUTATION_POLICY_VERSION', VERSION)
    raise ArgumentError, 'invalid reputation mode/version' unless %w[shadow warning enforce].include?(mode) && version == VERSION

    @settings = {
      warning: ratio(env, 'WARNING_RATIO', '0.02'), high_risk: ratio(env, 'HIGH_RISK_RATIO', '0.04'),
      pause: ratio(env, 'PAUSE_RATIO', '0.05'), attention: ratio(env, 'COMPLAINT_ATTENTION_RATIO', '0.0005'),
      complaint_pause: ratio(env, 'COMPLAINT_PAUSE_RATIO', '0.001'),
      min_permanent: Integer(env.fetch('EMAIL_REPUTATION_MIN_PERMANENT', '5'), 10)
    }.freeze
    validate_thresholds!
  rescue ArgumentError => e
    raise CustomExceptions::EmailReputationConfiguration, e.message
  end

  def evaluate(metrics)
    sent = metrics.fetch(:sent)
    bounce_ratio = local_ratio(metrics.fetch(:permanent), sent)
    complaint_ratio = local_ratio(metrics.fetch(:complaints), sent)
    reasons = pause_reasons(metrics, bounce_ratio, complaint_ratio)
    {
      level: reasons.any? ? 'paused' : risk_level(bounce_ratio, complaint_ratio),
      pause: reasons.any?, reasons: reasons, spam_alert: metrics.fetch(:complaints).positive?,
      permanent_ratio: sent.positive? ? bounce_ratio.to_f : nil, complaint_ratio: sent.positive? ? complaint_ratio.to_f : nil,
      # An empty/aged-out cohort is not proof of remediation. Release is explicit and conservative.
      resume_allowed: sent >= 50 && bounce_ratio < settings[:warning] && metrics.fetch(:complaints).zero?
    }
  end

  def snapshot
    { version: version, mode: mode, thresholds: settings.transform_values(&:to_s) }
  end

  private

  def local_ratio(count, sent)
    sent.positive? ? BigDecimal(count.to_s) / sent : BigDecimal(0)
  end

  def validate_thresholds!
    return if settings[:high_risk].between?(settings[:warning], settings[:pause]) &&
              settings[:attention] <= settings[:complaint_pause] && settings[:min_permanent].positive?

    raise ArgumentError, 'invalid reputation thresholds'
  end

  def pause_reasons(metrics, bounce_ratio, complaint_ratio)
    reasons = []
    reasons << 'permanent_failures' if bounce_ratio >= settings[:pause] && metrics.fetch(:permanent) >= settings[:min_permanent]
    reasons << 'complaints' if complaint_ratio >= settings[:complaint_pause] && metrics.fetch(:complaints).positive?
    reasons
  end

  def risk_level(bounce_ratio, complaint_ratio)
    return 'high_risk' if bounce_ratio >= settings[:high_risk]
    return 'attention' if complaint_ratio >= settings[:attention]
    return 'warning' if bounce_ratio >= settings[:warning]

    'healthy'
  end

  def ratio(env, key, default)
    value = BigDecimal(env.fetch("EMAIL_REPUTATION_#{key}", default))
    raise ArgumentError, "invalid #{key}" unless value.finite? && value.positive? && value <= 1

    value
  end
end
