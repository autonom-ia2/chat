# Local observations provide diagnostics and immutable alerts, never sending authority.
class EmailCampaigns::Reputation::Evaluator
  FLAG_KEY = 'email_campaigns_paused'.freeze

  def initialize(account, policy: EmailCampaigns::Reputation::Policy.new)
    @account_id = account.id
    @policy = policy
  end

  def evaluate!
    observed { |state| payload(state) }
  end

  def resume!(actor: nil, delivery_mode: 'ses') # rubocop:disable Lint/UnusedMethodArgument -- retained public keyword
    observed(delivery_mode: delivery_mode) do |state|
      provider = EmailCampaigns::Reputation::ProviderGate.protection if delivery_mode.to_s == 'ses'
      result = payload(state).merge(protection: provider, resume_allowed: provider.nil?)
      yield if provider.nil? && block_given?
      result
    end
  end

  # Keep the existing operator endpoint explicit while retiring tenant exceptions.
  def override!(actor:, **)
    raise Pundit::NotAuthorizedError unless actor && SuperAdmin.exists?(id: actor.id)

    raise CustomExceptions::EmailReputationOverride, 'account_override_not_required'
  end

  private

  # Collection stays outside Account/state/provider locks. Superseded local data is
  # not published and requests a fresh observation, without stopping unrelated sends.
  def observed(delivery_mode: nil)
    observation = EmailCampaigns::Reputation::Observation.new(@account_id).collect
    Account.find(@account_id).with_lock do
      state = EmailReputationState.find_by!(account_id: @account_id)
      state.with_lock do
        if observation.current?(state)
          refresh!(state, observation)
        else
          ActiveRecord.after_all_transactions_commit { EmailCampaigns::Reputation::EvaluationQueue.request(@account_id) }
        end
        EmailCampaigns::Reputation::ProviderGate.with_admission_lock(delivery_mode: delivery_mode) { yield state }
      end
    end
  end

  def refresh!(state, observation) # rubocop:disable Metrics/AbcSize -- publish diagnostics and their alert atomically
    decision = @policy.evaluate(observation.metrics)
    decision[:level] = 'high_risk' if decision[:level] == 'paused'
    previous = state.current_metrics
    published = observation.metrics.merge(decision.except(:pause, :resume_allowed)).merge(evaluation_generation: observation.generation)
    changed_risk = state.level != decision[:level] && decision[:level] != 'healthy'
    new_complaint = observation.metrics.fetch(:complaints) > previous.fetch('complaints', 0)
    state.update!(current_metrics: published.stringify_keys, policy: @policy.snapshot,
                  evaluated_at: Time.current, level: decision[:level], evaluated_feedback_version: observation.feedback_version)
    return if @policy.mode == 'shadow' || !(changed_risk || new_complaint)

    EmailReputationAudit.create!(account_id: @account_id, action: 'risk_alert', snapshot: payload(state))
  end

  def payload(state)
    EmailCampaigns::Reputation::Payload.for_state(state)
  end
end
