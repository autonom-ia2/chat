class EmailCampaigns::Maintenance::Config
  class Invalid < StandardError; end

  def initialize(env = ENV)
    @enabled = env.fetch('EMAIL_CAMPAIGN_PROTECTION_BACKFILL_ENABLED', 'false')
    raise Invalid, 'invalid_backfill_configuration' unless %w[true false].include?(@enabled)
  end

  def apply_enabled?
    @enabled == 'true'
  end
end
