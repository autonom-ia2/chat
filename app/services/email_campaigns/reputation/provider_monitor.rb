# Read-only SES GetAccount + CloudWatch GetMetricStatistics. Never called by admission.
class EmailCampaigns::Reputation::ProviderMonitor
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
    # Only collection errors are converted to unknown. Persistence bugs must fail loudly.
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
      require 'aws-sdk-cloudwatch' # Already present via speedshop-cloudwatch; no new dependency.
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
    state.with_lock do
      # Older overlapping polls cannot replace newer telemetry. A late harmful
      # observation may still add the irreversible provider latch/audit, but never
      # rewinds checked_at/status/telemetry or releases anything.
      if state.checked_at && state.checked_at >= attributes.fetch(:checked_at)
        latch_superseded_block!(state, attributes)
        return state
      end

      update_observation!(state, attributes)
    end
    state
  end

  def latch_superseded_block!(state, attributes)
    return unless attributes[:status] == 'blocked'

    newly_blocked = !state.blocked
    state.update!(blocked: true, harmful_generation: state.harmful_generation + 1)
    return unless newly_blocked

    EmailReputationAudit.create!(provider_key: state.provider_key, action: 'provider_blocked',
                                 snapshot: { code: 'provider_blocked', checked_at: attributes[:checked_at],
                                             observed_at: attributes[:observed_at], superseded: true })
  end

  def update_observation!(state, attributes)
    harmful = attributes[:status] == 'blocked'
    attributes[:status] = 'blocked' if state.status == 'blocked' && attributes[:status] == 'unknown'
    newly_blocked = !state.blocked && (state.latched? || harmful)
    apply_block_attributes!(state, attributes, harmful, newly_blocked)
    state.update!(attributes)
    return unless newly_blocked

    EmailReputationAudit.create!(provider_key: state.provider_key, action: 'provider_blocked',
                                 snapshot: { code: 'provider_blocked', checked_at: state.checked_at })
  end

  def apply_block_attributes!(state, attributes, harmful, newly_blocked)
    return unless harmful || newly_blocked

    attributes[:blocked] = true
    attributes[:harmful_generation] = state.harmful_generation + 1 if harmful
  end
end
