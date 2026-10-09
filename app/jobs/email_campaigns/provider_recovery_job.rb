class EmailCampaigns::ProviderRecoveryJob < ApplicationJob
  queue_as :scheduled_jobs

  PROVIDER_CODES = %w[provider_blocked provider_telemetry_unknown].freeze

  def perform(provider_key, harmful_generation)
    return unless EmailCampaigns::Config.enabled?

    config = EmailCampaigns::Reputation::ProviderConfig.new
    return unless config.enabled && config.provider_key == provider_key

    state = EmailProviderState.find_by(provider_key: provider_key)
    return unless state && state.harmful_generation == harmful_generation
    return if EmailCampaigns::Reputation::ProviderGate.protection(config: config)

    provider_paused_campaigns.find_each do |campaign|
      resume_campaign(campaign)
    end
  end

  private

  def provider_paused_campaigns
    EmailCampaign.ses.paused
                 .where("pause_reason ->> 'kind' = ?", 'provider')
                 .where("pause_reason ->> 'code' IN (?)", PROVIDER_CODES)
  end

  def resume_campaign(campaign)
    campaign.resume!
  rescue CustomExceptions::EmailReputationBlocked
    # Hygiene/import races remain authoritative. A later operator action can resume.
    nil
  end
end
