class EmailCampaigns::PreflightDecision
  PAUSE_REASON = 'hygiene_validation_required'.freeze

  def initialize(config: EmailCampaigns::HygieneConfig.new)
    @config = config
  end

  # No DNS or writes. Suitable for later guardrail/report/UI integration.
  def call(recipient)
    fresh = recipient.preflight_status == 'valid' && recipient.preflight_valid_until.present? && recipient.preflight_valid_until > Time.current
    { allowed: !@config.enforce? || fresh, mode: @config.mode, status: recipient.preflight_status,
      reason_code: fresh ? nil : recipient.preflight_reason_code || 'unchecked',
      suggestion: recipient.preflight_suggestion, warning: @config.mode == 'warning' && !fresh }
  end

  def unresolved(campaign)
    campaign.email_campaign_recipients.pending.where(
      "preflight_status != 'valid' OR preflight_valid_until IS NULL OR preflight_valid_until <= ?", Time.current
    )
  end

  def campaign_allowed?(campaign)
    return false if campaign.recipient_import_active?
    return true unless @config.enforce?

    # Reuse the authoritative active union, bounded to each pending candidate batch.
    # Do not persist suppression/preflight changes or reset strong blocks here.
    unresolved(campaign).in_batches(of: 500) do |batch|
      emails = batch.pluck(:email)
      blocked = EmailSuppression.blocking_reasons_for(campaign.account, emails)
      return false if emails.any? { |email| !blocked.key?(email.strip.downcase) }
    end
    true
  end

  def pause!(campaign)
    # Never overwrite a manual, tenant or SES pause. Revalidation never resumes.
    EmailCampaign.where(id: campaign.id, status: %i[sending scheduled]).update_all( # rubocop:disable Rails/SkipsModelValidations
      status: EmailCampaign.statuses[:paused], hygiene_pause_reason: PAUSE_REASON, updated_at: Time.current
    )
  end
end
