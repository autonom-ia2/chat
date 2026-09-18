# Persisted internal ratios stay fractions. The public UI contract uses percentages.
class EmailCampaigns::Presentation::ProtectionMetrics
  COUNTS = { sent: 'sent', permanent_bounces: 'permanent', temporary_bounces: 'transient',
             unknown_bounces: 'unknown', complaints: 'complaints' }.freeze

  def initialize(metrics, evaluated_at: nil)
    @metrics = metrics || {}
    @evaluated_at = evaluated_at
  end

  def call
    COUNTS.transform_values { |key| @metrics[key] }.merge(
      hard_bounce_rate: percent('permanent_ratio'), complaint_rate: percent('complaint_ratio'),
      evaluated_at: @evaluated_at, window_start: @metrics['cohort_start'], window_end: @metrics['cohort_end']
    )
  end

  private

  def percent(key)
    return unless @metrics['sent'].is_a?(Integer) && @metrics['sent'].positive?

    ratio = @metrics[key]
    return if ratio.nil?

    raise ArgumentError, 'invalid persisted reputation ratio' unless ratio.is_a?(Numeric) && ratio.finite? && ratio >= 0

    (ratio * 100).round(4)
  end
end
