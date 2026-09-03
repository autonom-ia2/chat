class Sla::TriggerSlasForAccountsJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    # Só processa SLA de contas com a feature `sla` ligada (mesmo gate do Crm::SlaAutoApplyJob);
    # uma conta com SLA policy mas feature off (ex.: downgrade de plano) não deve ser processada.
    # Upstream 4.17 filters in SQL via the FlagShihTzu scope instead of per-account in Ruby.
    Account.feature_sla.joins(:sla_policies).distinct.find_each do |account|
      Rails.logger.info "Enqueuing ProcessAccountAppliedSlasJob for account #{account.id}"
      Sla::ProcessAccountAppliedSlasJob.perform_later(account)
    end
  end
end
