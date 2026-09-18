class EmailCampaigns::ReputationEvaluationJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform(account_id, lease_token = nil)
    return unless EmailCampaigns::Config.enabled?
    return if lease_token && !EmailReputationState.exists?(account_id: account_id, evaluation_lease_token: lease_token)

    account = Account.find_by(id: account_id)
    EmailCampaigns::Guardrail.evaluate!(account) if account
    EmailCampaigns::Reputation::EvaluationQueue.finish(account_id, lease_token) if lease_token
  end
end
