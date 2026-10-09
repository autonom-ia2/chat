class EmailCampaigns::HygieneConfig
  attr_reader :mode, :temporary_threshold, :temporary_window, :quarantine_duration

  def initialize(env = ENV)
    @mode = env.fetch('EMAIL_CAMPAIGN_HYGIENE_MODE', 'shadow')
    raise ArgumentError, 'invalid EMAIL_CAMPAIGN_HYGIENE_MODE' unless %w[shadow warning enforce].include?(@mode)

    @dns_enabled = env.fetch('EMAIL_CAMPAIGN_HYGIENE_DNS_ENABLED', 'false')
    raise ArgumentError, 'invalid EMAIL_CAMPAIGN_HYGIENE_DNS_ENABLED' unless %w[true false].include?(@dns_enabled)

    @temporary_threshold = integer(env, 'EMAIL_CAMPAIGN_SOFT_BOUNCE_THRESHOLD', 3, 1..100)
    @temporary_window = integer(env, 'EMAIL_CAMPAIGN_SOFT_BOUNCE_WINDOW_DAYS', 7, 1..365) * 86_400
    @quarantine_duration = integer(env, 'EMAIL_CAMPAIGN_QUARANTINE_HOURS', 72, 1..8760) * 3600
  end

  def dns_enabled?
    @dns_enabled == 'true'
  end

  def enforce?
    mode == 'enforce'
  end

  private

  def integer(env, key, default, range)
    raw = env.fetch(key, default.to_s)
    raise ArgumentError, "invalid #{key}" unless raw.match?(/\A[0-9]+\z/)

    value = Integer(raw, 10)
    raise ArgumentError, "invalid #{key}" unless range.cover?(value)

    value
  end
end
