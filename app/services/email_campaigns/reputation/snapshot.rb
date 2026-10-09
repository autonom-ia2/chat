class EmailCampaigns::Reputation::Snapshot
  def self.capture(state, legacy, now: Time.current)
    at = legacy_time(legacy, now)
    { triggered_at: at.iso8601, code: legacy.present? ? 'legacy_pause' : 'reputation_threshold',
      metrics: legacy.present? ? nil : state.current_metrics, policy: legacy.present? ? nil : state.policy }
  end

  def self.legacy_time(legacy, now)
    value = legacy.is_a?(Hash) ? legacy['at'] : nil
    return now unless value.is_a?(String)

    parsed = Time.iso8601(value)
    [parsed, now].min
  rescue ArgumentError
    now
  end
  private_class_method :legacy_time
end
