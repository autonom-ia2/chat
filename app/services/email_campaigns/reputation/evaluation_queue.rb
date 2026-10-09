# Durable lease: at most one queued evaluation per account during the lease interval.
# Feedback advances a version even when coalesced; completion schedules a follow-up if needed.
# A crashed worker/lost enqueue is recovered by the periodic reconciliation sweep.
class EmailCampaigns::Reputation::EvaluationQueue
  LEASE_SECONDS = 300

  # Must run inside the feedback write transaction, before its commit becomes visible.
  def self.invalidate(account_id)
    state = EmailReputationState.for_account(account_id)
    state.with_lock { state.update!(feedback_version: state.feedback_version + 1) }
  end

  def self.request(account_id)
    state = EmailReputationState.for_account(account_id)
    token = state.with_lock do
      lease = claim(state)
      state.save!
      lease
    end
    EmailCampaigns::ReputationEvaluationJob.perform_later(account_id, token) if token
  end

  def self.finish(account_id, token)
    state = EmailReputationState.find_by(account_id: account_id)
    return unless state

    next_token = state.with_lock do
      next unless state.evaluation_lease_token == token

      state.evaluation_lease_until = nil
      state.evaluation_lease_token = nil
      lease = claim(state) if state.feedback_version > state.evaluated_feedback_version
      state.save!
      lease
    end
    EmailCampaigns::ReputationEvaluationJob.perform_later(account_id, next_token) if next_token
  end

  def self.claim(state)
    return if state.evaluation_lease_until && state.evaluation_lease_until > Time.current

    state.evaluation_lease_until = Time.current + LEASE_SECONDS
    state.evaluation_lease_token = SecureRandom.uuid
  end
  private_class_method :claim
end
