# Explicit tenant allowlist. Operator reasons, actor, budget and history stay in audit routes.
class EmailCampaigns::Reputation::Payload
  def self.for_state(state)
    {
      blocked: false, level: state.level == 'paused' ? 'high_risk' : state.level, evaluated_at: state.evaluated_at,
      current_metrics: state.current_metrics, policy: state.policy,
      trigger_snapshot: state.trigger_snapshot.slice('triggered_at', 'code', 'metrics', 'policy'),
      override_active: false,
      resume_allowed: true
    }
  end
end
