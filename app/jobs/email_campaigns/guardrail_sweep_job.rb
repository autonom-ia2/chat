class EmailCampaigns::GuardrailSweepJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    return unless EmailCampaigns::Config.enabled?

    # Reconcile durable feedback, old legacy flags and paused tenants even without recent sends.
    Account.where(id: EmailCampaign.select(:account_id))
           .or(Account.where(id: EmailReputationState.select(:account_id)))
           .or(Account.where("internal_attributes ? 'email_campaigns_paused'"))
           .find_each { |account| EmailCampaigns::Guardrail.evaluate!(account) }
  end
end
