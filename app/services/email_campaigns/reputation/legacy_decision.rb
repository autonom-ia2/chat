# Rollout adapter only: same cohort/metrics, old > thresholds and 50-send floor.
# Enforce mode replaces this decision with the versioned classified policy.
class EmailCampaigns::Reputation::LegacyDecision
  def self.resume_allowed?(metrics, proposed:)
    proposed && !pause?(metrics)
  end

  def self.pause?(metrics)
    sent = metrics.fetch(:sent)
    sent >= 50 && (metrics.fetch(:bounced) * 100 > sent * 5 || metrics.fetch(:complaints) * 1000 > sent * 3)
  end
end
