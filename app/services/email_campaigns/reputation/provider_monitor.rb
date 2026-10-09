# Read-only provider account + CloudWatch reputation telemetry. Never called by admission.
class EmailCampaigns::Reputation::ProviderMonitor
  RECOVERY_STREAK_KEY = 'recovery_streak'.freeze
  RECOVERY_OBSERVED_AT_KEY = 'recovery_observed_at'.freeze

  def initialize(config: EmailCampaigns::Reputation::ProviderConfig.new, ses: nil, cloudwatch: nil)
    @config = config
    @ses = ses
    @cloudwatch = cloudwatch
  end

  def call
    return unless @config.enabled

    checked_at = Time.current
    persist(collect(checked_at).merge(checked_at: checked_at))
  end

  private

  def collect(checked_at)
    account = (@ses || EmailCampaigns::Ses::Client.new).get_account
    observation(account, checked_at).merge(error_code: nil)
  rescue StandardError => e
    { status: 'unknown', error_code: e.class.name }
  end

  def observation(account, now)
    telemetry = { sending_enabled: account['SendingEnabled'], enforcement_status: account['EnforcementStatus'] }
    if account['SendingEnabled'] == false || %w[PROBATION SHUTDOWN].include?(account['EnforcementStatus'])
      return { status: 'blocked', telemetry: telemetry, observed_at: now }
    end

    bounce = metric('Reputation.BounceRate', now)
    if critical_ratio?(bounce, @config.bounce_ratio)
      return { status: 'blocked', telemetry: telemetry.merge(bounce: bounce), observed_at: bounce.fetch(:observed_at) }
    end

    complaint = metric('Reputation.ComplaintRate', now)
    { status: observed_status(account, bounce, complaint), telemetry: telemetry.merge(bounce: bounce, complaint: complaint),
      observed_at: [bounce&.fetch(:observed_at), complaint&.fetch(:observed_at)].compact.min }
  end

  def observed_status(account, bounce, complaint)
    return 'blocked' if critical_ratio?(complaint, @config.complaint_ratio)
    return 'unknown' unless bounce && complaint
    return 'healthy' if account.values_at('SendingEnabled', 'EnforcementStatus') == [true, 'HEALTHY']

    'unknown'
  end

  def critical_ratio?(point, threshold)
    point && point[:ratio] >= threshold
  end

  def cloudwatch
    @cloudwatch ||= begin
      require 'aws-sdk-cloudwatch'
      options = { region: EmailCampaigns::Config.region, http_open_timeout: 5, http_read_timeout: 10, retry_limit: 1 }
      credentials = EmailCampaigns::Config.static_credentials
      options[:credentials] = credentials if credentials
      Aws::CloudWatch::Client.new(**options)
    end
  end

  def metric(name, now)
    response = cloudwatch.get_metric_statistics(namespace: 'AWS/SES', metric_name: name, dimensions: [],
                                                start_time: now - @config.max_age, end_time: now, period: 300,
                                                statistics: ['Average'])
    point = response.datapoints.select { |item| item.timestamp.between?(now - @config.max_age, now) }.max_by(&:timestamp)
    return unless point

    value = Float(point.average)
    raise ArgumentError, 'invalid provider ratio' unless value.finite? && value.between?(0, 1)

    { ratio: value, observed_at: point.timestamp }
  end

  def persist(attributes)
    state = EmailProviderState.for_provider(@config.provider_key)
    should_recover_campaigns = false
    state.with_lock do
      if state.checked_at && state.checked_at >= attributes.fetch(:checked_at)
        latch_superseded_block!(state, attributes)
        return state
      end

      should_recover_campaigns = update_observation!(state, attributes)
    end
    enqueue_recovery(state) if should_recover_campaigns
    state
  end

  # A late harmful poll can only add protection. A late healthy poll can never release it.
  def latch_superseded_block!(state, attributes)
    return unless attributes[:status] == 'blocked'

    newly_blocked = !state.blocked
    telemetry = state.telemetry.deep_dup
    telemetry[RECOVERY_STREAK_KEY] = 0
    state.update!(blocked: true, harmful_generation: state.harmful_generation + 1, telemetry: telemetry)
    audit!(state, 'provider_blocked', attributes, superseded: true) if newly_blocked
  end

  def update_observation!(state, attributes)
    harmful = harmful_observation?(attributes)
    newly_blocked = harmful && !state.blocked
    unavailable_before = provider_unavailable_before?(state, attributes)
    normalize_unknown_status!(state, attributes)
    recovered = apply_transition!(state, attributes, harmful)

    state.update!(attributes)
    audit!(state, 'provider_blocked', attributes) if newly_blocked
    audit!(state, 'provider_recovered', attributes) if recovered
    recovery_job_needed?(state, attributes, recovered, unavailable_before)
  end

  def harmful_observation?(attributes)
    attributes[:status] == 'blocked'
  end

  def normalize_unknown_status!(state, attributes)
    return unless state.status == 'blocked' && attributes[:status] == 'unknown'

    attributes[:status] = 'blocked'
  end

  def apply_transition!(state, attributes, harmful)
    return apply_harmful!(state, attributes) if harmful
    return apply_recovery!(state, attributes) if state.blocked

    false
  end

  def apply_harmful!(state, attributes)
    attributes[:blocked] = true
    attributes[:harmful_generation] = state.harmful_generation + 1
    attributes[:telemetry] = recovery_telemetry(state, attributes, streak: 0)
    false
  end

  def recovery_job_needed?(state, attributes, recovered, unavailable_before)
    recovered || (attributes[:status] == 'healthy' && !state.blocked && unavailable_before)
  end

  def provider_unavailable_before?(state, attributes)
    return true if state.status != 'healthy' || state.error_code.present?
    return true if state.checked_at.nil?

    state.checked_at < attributes.fetch(:checked_at) - @config.max_age
  end

  def apply_recovery!(state, attributes)
    attributes[:blocked] = true
    streak = recovery_streak(state, attributes)
    attributes[:telemetry] = recovery_telemetry(state, attributes, streak: streak)
    return false unless recovery_releasable?(state, streak)

    attributes[:blocked] = false
    attributes[:telemetry][RECOVERY_STREAK_KEY] = 0
    true
  end

  def recovery_streak(state, attributes)
    return 0 unless attributes[:status] == 'healthy'
    return 0 unless observation_advanced?(state, attributes)
    return 0 unless recovery_safe?(attributes)

    state.telemetry.fetch(RECOVERY_STREAK_KEY, 0).to_i + 1
  end

  def observation_advanced?(state, attributes)
    observed_at = attributes[:observed_at]
    observed_at.present? && (state.observed_at.nil? || observed_at > state.observed_at)
  end

  def recovery_releasable?(state, streak)
    streak >= @config.recovery_observations && !@config.manual_block && !state.manual_block
  end

  def recovery_safe?(attributes)
    telemetry = attributes[:telemetry] || {}
    bounce = telemetry.dig(:bounce, :ratio)
    complaint = telemetry.dig(:complaint, :ratio)
    bounce.is_a?(Numeric) && complaint.is_a?(Numeric) &&
      bounce < @config.bounce_recovery_ratio && complaint < @config.complaint_recovery_ratio
  end

  def recovery_telemetry(state, attributes, streak:)
    telemetry = state.telemetry.deep_dup
    telemetry.merge!((attributes[:telemetry] || {}).deep_stringify_keys)
    telemetry[RECOVERY_STREAK_KEY] = streak
    telemetry[RECOVERY_OBSERVED_AT_KEY] = attributes[:observed_at]&.iso8601
    telemetry
  end

  def audit!(state, action, attributes, superseded: false)
    EmailReputationAudit.create!(
      provider_key: state.provider_key,
      action: action,
      snapshot: {
        code: action,
        checked_at: attributes[:checked_at],
        observed_at: attributes[:observed_at],
        superseded: superseded,
        recovery_observations: @config.recovery_observations
      }
    )
  end

  def enqueue_recovery(state)
    generation = state.harmful_generation
    ActiveRecord.after_all_transactions_commit do
      EmailCampaigns::ProviderRecoveryJob.perform_later(state.provider_key, generation)
    end
  end
end
