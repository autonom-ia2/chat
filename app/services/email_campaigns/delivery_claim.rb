class EmailCampaigns::DeliveryClaim
  def initialize(campaign)
    @campaign = campaign
    @decision = EmailCampaigns::PreflightDecision.new
    @admission = EmailCampaigns::Reputation::Admission.new(campaign)
  end

  # Check before rendering without reserving a recipient or spending override budget.
  def prepare(recipient)
    @admission.with_delivery_locks(recipient) { eligibility(recipient, :pending) }
  end

  # Final authorization after rendering. No rendering, DNS or provider I/O under locks.
  def claim(recipient)
    result = @admission.with_delivery_locks(recipient, provider: true) do |state|
      eligible = eligibility(recipient, :pending)
      next eligible unless eligible == :ready

      # The recipient lock reloads status; the conditional update also fences duplicate claims.
      claimed = EmailCampaignRecipient.where(id: recipient.id, email_campaign_id: @campaign.id, status: :pending)
                                      .update_all(status: EmailCampaignRecipient.statuses[:sent], updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      next :skipped unless claimed.positive?

      @admission.consume_override!(state) if state&.override_active?
      recipient.reload
      :claimed
    end
    @claimed_id = recipient.id if result == :claimed
    result
  end

  # Compatibility for the old two-phase caller. Only this gate's undispatched claim
  # can be checked/released. New engines render before claim and dispatch immediately.
  def dispatch_allowed?(recipient)
    return false unless @claimed_id == recipient.id

    # A successful dispatch check is the handoff boundary. A later ambiguous call
    # cannot reuse this gate to release an already authorized message.
    @claimed_id = nil
    @admission.with_delivery_locks(recipient, provider: true) do
      eligible = eligibility(recipient, :sent)
      next true if eligible == :ready

      release_claim(recipient) if recipient.sent? && unreceipted?(recipient)
      false
    end
  end

  private

  def eligibility(recipient, expected_status) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity -- keep authorization gates together
    return :skipped unless recipient.email_campaign_id == @campaign.id && recipient.status == expected_status.to_s
    return :skipped unless unreceipted?(recipient)
    return suppress(recipient) if EmailSuppression.suppressed?(@campaign.account, recipient.email)
    return :skipped unless @campaign.sending?
    return :skipped if @campaign.recipient_import_active?
    return :paused if @admission.park_if_blocked!
    return :ready if @decision.call(recipient)[:allowed]

    @decision.pause!(@campaign)
    # pause! uses conditional SQL. Keep this clean locked instance consistent so a
    # later explicit transition is not lost to Rails' partial-update dirty tracking.
    @campaign.reload
    :paused
  end

  def unreceipted?(recipient)
    recipient.sent_at.nil? && recipient.ses_message_id.blank?
  end

  def release_claim(recipient)
    # This compatibility caller has demonstrably not reached a provider.
    next_status = @campaign.terminal? ? :suppressed : :pending
    recipient.update_columns( # rubocop:disable Rails/SkipsModelValidations
      status: EmailCampaignRecipient.statuses.fetch(next_status.to_s), updated_at: Time.current
    )
  end

  def suppress(recipient)
    recipient.update_columns(status: EmailCampaignRecipient.statuses[:suppressed], updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    :suppressed
  end
end
