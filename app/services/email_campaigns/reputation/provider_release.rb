# Explicit global operator action. A healthy observation only makes a latch reviewable.
class EmailCampaigns::Reputation::ProviderRelease
  def initialize(config: EmailCampaigns::Reputation::ProviderConfig.new, monitor: nil)
    @config = config
    @monitor = monitor || EmailCampaigns::Reputation::ProviderMonitor.new(config: config)
  end

  def call(actor:, reason:)
    raise Pundit::NotAuthorizedError unless actor && SuperAdmin.exists?(id: actor.id)

    validate_release!(reason)

    state = @monitor.call
    state.with_lock do
      raise CustomExceptions::EmailReputationOverride, 'provider_release_denied' unless releasable?(state)

      state.update!(blocked: false, manual_block: false, manual_reason: nil)
      EmailReputationAudit.create!(provider_key: state.provider_key, actor_id: actor.id, action: 'provider_released',
                                   snapshot: { reason: reason.strip, checked_at: state.checked_at, code: 'provider_released' })
    end
    { code: 'provider_released' }
  end

  private

  def validate_release!(reason)
    return if reason.is_a?(String) && reason.strip.length.between?(10, 500) && @config.enabled && !@config.manual_block

    raise CustomExceptions::EmailReputationOverride, 'provider_release_denied'
  end

  def releasable?(state)
    state.status == 'healthy' && state.error_code.nil? &&
      state.observed_at&.between?(Time.current - @config.max_age, Time.current) &&
      state.telemetry.values_at('sending_enabled', 'enforcement_status') == [true, 'HEALTHY'] &&
      safe_ratio?(state, 'bounce', @config.bounce_ratio) && safe_ratio?(state, 'complaint', @config.complaint_ratio)
  end

  def safe_ratio?(state, name, threshold)
    ratio = state.telemetry.dig(name, 'ratio')
    ratio.is_a?(Numeric) && ratio.finite? && ratio >= 0 && ratio < threshold
  end
end
