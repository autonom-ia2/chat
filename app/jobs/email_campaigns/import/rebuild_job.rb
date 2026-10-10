# Rebuilds one part of an imported model with the AI (#1099, delivery D), for the click that holds the part's token.
# Every failure is caught and stored on the part by PartRebuild, so nothing reaches Sidekiq to retry: a retry would ask
# the AI (and pay for it) again.
class EmailCampaigns::Import::RebuildJob < ApplicationJob
  queue_as :medium

  def perform(import_id, target, token)
    import = EmailCampaignTemplateImport.find_by(id: import_id)
    return if import.nil?

    EmailCampaigns::Import::PartRebuild.call(import, target, token)
  end
end
