# Bounded DB reads only. Gate nil means permitted, not proof of healthy monitoring.
class EmailCampaigns::Presentation::ProtectionProvider
  def initialize(now: Time.current)
    @now = now
  end

  def call(direct: false)
    return { state: 'not_applicable', observed_at: nil, blocked: false } if direct

    @call ||= read
  end

  private

  def read
    config = EmailCampaigns::Reputation::ProviderConfig.new
    state = EmailProviderState.find_by(provider_key: config.provider_key) if config.enabled
    # Read the authoritative gate after display telemetry, so a newer block wins.
    gate = EmailCampaigns::Reputation::ProviderGate.protection(config: config, now: @now)
    return { state: 'blocked', observed_at: gate[:observed_at], blocked: true } if gate

    return { state: 'unknown', observed_at: nil, blocked: false } unless config.enabled

    present(state, config)
  end

  def present(state, config)
    status = state&.status || 'unknown'
    raise ArgumentError, 'unknown persisted provider status' unless %w[unknown healthy blocked].include?(status)

    fresh = state&.observed_at&.between?(@now - config.max_age, @now)
    { state: fresh ? status : 'unknown', observed_at: state&.observed_at, blocked: state&.latched? == true }
  end
end
