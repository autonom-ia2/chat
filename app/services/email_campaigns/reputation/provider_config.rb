class EmailCampaigns::Reputation::ProviderConfig
  attr_reader :enabled, :provider_key, :max_age, :unknown_action, :manual_block, :bounce_ratio, :complaint_ratio

  def initialize(env = ENV)
    @bounce_ratio = threshold(env, 'BOUNCE_RATIO', '0.05', 0.05)
    @complaint_ratio = threshold(env, 'COMPLAINT_RATIO', '0.001', 0.001)
    @enabled = boolean(env.fetch('EMAIL_REPUTATION_PROVIDER_MONITOR', 'false'))
    @manual_block = boolean(env.fetch('EMAIL_REPUTATION_PROVIDER_BLOCK', 'false'))
    @provider_key = "ses:#{provider_account(env)}:#{EmailCampaigns::Config.region}"
    @max_age = Integer(env.fetch('EMAIL_REPUTATION_PROVIDER_MAX_AGE_SECONDS', '900'), 10)
    @unknown_action = env.fetch('EMAIL_REPUTATION_PROVIDER_UNKNOWN_ACTION', 'block')
    raise ArgumentError, 'invalid provider freshness configuration' unless max_age.between?(300, 3600) && %w[block allow].include?(unknown_action)
  rescue ArgumentError => e
    raise CustomExceptions::EmailReputationConfiguration, e.message
  end

  private

  def threshold(env, key, default, maximum)
    value = Float(env.fetch("EMAIL_REPUTATION_PROVIDER_#{key}", default))
    raise ArgumentError, 'invalid provider threshold' unless value.finite? && value.positive? && value <= maximum

    value
  end

  def provider_account(env)
    account = env.fetch('EMAIL_REPUTATION_AWS_ACCOUNT_ID', '')
    return 'unconfigured' if account.empty? && !enabled
    raise ArgumentError, 'valid provider AWS account id is required' unless account.match?(/\A\d{12}\z/)

    account
  end

  def boolean(value)
    raise ArgumentError, 'invalid provider boolean' unless %w[true false].include?(value)

    value == 'true'
  end
end
