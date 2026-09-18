class EmailCampaigns::ProtectionBackfillReconcileJob < ApplicationJob
  queue_as :housekeeping

  def perform
    # Only an outbox backstop: never discovers accounts or creates runs.
    EmailProtectionMaintenanceRun.due.order(:next_dispatch_at, :id).limit(100).pluck(:id).each do |id|
      EmailCampaigns::Maintenance::Dispatch.call(id)
    end
  end
end
