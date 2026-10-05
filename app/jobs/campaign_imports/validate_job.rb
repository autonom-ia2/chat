class CampaignImports::ValidateJob < ApplicationJob
  queue_as :low

  def perform(campaign_import)
    return unless CampaignImports::Config.enabled?

    validator_for(campaign_import).new(campaign_import).perform
  end

  private

  def validator_for(campaign_import)
    return ContactImports::Validator if campaign_import.contact_import?

    campaign_import.audience? ? CampaignImports::AudienceValidator : CampaignImports::Validator
  end
end
