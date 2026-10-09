# Explicit tenant allowlist. Operator reasons, actor, budget and history stay in audit routes.
class EmailCampaigns::Reputation::Payload
  def self.for_state(state)
    {
      blocked: state.blocked, level: state.level, evaluated_at: state.evaluated_at,
      current_metrics: state.current_metrics, policy: state.policy,
      trigger_snapshot: state.trigger_snapshot.slice('triggered_at', 'code', 'metrics', 'policy'),
      override_active: state.override_active?,
      resume_allowed: !state.blocked || state.override_active? || state.current_metrics.fetch('resume_allowed', false)
    }
  end
end
