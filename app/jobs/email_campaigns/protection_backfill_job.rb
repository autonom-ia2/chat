class EmailCampaigns::ProtectionBackfillJob < ApplicationJob
  queue_as :housekeeping

  def perform(run_id)
    run = EmailProtectionMaintenanceRun.find_by(id: run_id)
    return unless run

    EmailCampaigns::Maintenance::HistoricalProtectionBackfill.new(run: run).call
  end
end
