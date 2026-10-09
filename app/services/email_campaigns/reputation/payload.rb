# Public tenant payload: local reputation is diagnostic-only. Historical trigger
# snapshots remain visible for audit, but cannot block or require an override.
class EmailCampaigns::Reputation::Payload
  def self.for_state(state)
    {
      blocked: false,
      level: state.level,
      evaluated_at: state.evaluated_at,
      current_metrics: state.current_metrics,
      policy: state.policy,
      trigger_snapshot: state.trigger_snapshot.slice('triggered_at', 'code', 'metrics', 'policy'),
      override_active: false,
      resume_allowed: true
    }
  end
end
