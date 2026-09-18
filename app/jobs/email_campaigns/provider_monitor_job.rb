class EmailCampaigns::ProviderMonitorJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    return unless EmailCampaigns::Config.enabled?

    EmailCampaigns::Reputation::ProviderMonitor.new.call
  end
end
