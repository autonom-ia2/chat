# Removes template imports nobody saved, 7 days after they started (#1099, delivery B), with their copied images. A
# saved import stays: the images of the template in "Meus modelos" are its attachments.
class EmailCampaigns::Import::CleanupJob < ApplicationJob
  queue_as :housekeeping

  def perform
    EmailCampaignTemplateImport.expired.find_each(&:destroy!)
  end
end
