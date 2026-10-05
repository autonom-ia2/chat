# frozen_string_literal: true

# Campaign journey (epic #990) extends Chatwoot campaign behaviour without editing
# upstream files: each extension is a fork module prepended here.
Rails.application.config.to_prepare do
  controller = Api::V1::Accounts::CampaignsController
  controller.prepend(CampaignJourney::WhatsappCloudGuard) unless controller.ancestors.include?(CampaignJourney::WhatsappCloudGuard)
end
