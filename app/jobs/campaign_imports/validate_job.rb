class CampaignImports::ValidateJob < ApplicationJob
  queue_as :low

  def perform(campaign_import)
    return unless CampaignImports::Config.enabled?

    validator = campaign_import.audience? ? CampaignImports::AudienceValidator : CampaignImports::Validator
    validator.new(campaign_import).perform
  end
end
