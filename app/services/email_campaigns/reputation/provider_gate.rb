class EmailCampaigns::Reputation::ProviderGate
  class << self
    # Compound writers acquire Account -> reputation state -> provider -> campaign -> recipient.
    # Monitor/release take only provider, after external collection; never acquire Account from there.
    def with_admission_lock(delivery_mode: 'ses', &)
      return yield unless delivery_mode.to_s == 'ses'

      config = EmailCampaigns::Reputation::ProviderConfig.new
      return yield unless config.enabled

      EmailProviderState.for_provider(config.provider_key).with_lock(&)
    end

    def protection(config: EmailCampaigns::Reputation::ProviderConfig.new, now: Time.current)
      state = EmailProviderState.find_by(provider_key: config.provider_key)
      code = block_code(state, config, now)
      return unless code

      # Never disclose provider account identifiers or another tenant's data to tenant APIs.
      { kind: 'provider', code: code, observed_at: state&.observed_at, overridable: false }
    end

    private

    def manually_blocked?(state, config)
      config.manual_block || state&.manual_block
    end

    def fresh_and_healthy?(state, config, now)
      state&.status == 'healthy' && state.observed_at&.between?(now - config.max_age, now)
    end

    def block_code(state, config, now)
      return 'provider_manual_block' if manually_blocked?(state, config)
      return 'provider_blocked' if state&.latched?
      return unless config.enabled && config.unknown_action == 'block'
      return 'provider_telemetry_unknown' unless fresh_and_healthy?(state, config, now)

      nil
    end
  end
end
