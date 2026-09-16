class EmailCampaigns::DeliveryClaim
  def initialize(campaign)
    @campaign = campaign
    @decision = EmailCampaigns::PreflightDecision.new
  end

  def claim(recipient)
    result = recipient.with_lock do
      return :skipped unless recipient.pending?
      return :skipped if recipient.sent_at.present? || recipient.ses_message_id.present?
      return suppress(recipient) if EmailSuppression.suppressed?(@campaign.account, recipient.email)
      next :paused unless @decision.call(recipient)[:allowed]

      # Claim transitions intentionally bypass identity validation while locked.
      recipient.update_columns(status: EmailCampaignRecipient.statuses[:sent], updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      :claimed
    end
    @decision.pause!(@campaign) if result == :paused
    result
  end

  # Call after rendering, immediately before provider dispatch. The caller owns the
  # claim. No network work is done while holding a database lock/transaction.
  def dispatch_allowed?(recipient)
    # Campaign -> recipient order matches cancellation/finalization. Both short
    # locks are released before the caller invokes the provider.
    @campaign.with_lock do
      recipient.with_lock do
        check_dispatch(recipient)
      end
    end
  end

  private

  def check_dispatch(recipient)
    return false unless recipient.sent?
    return false if recipient.sent_at.present? || recipient.ses_message_id.present?

    if EmailSuppression.suppressed?(@campaign.account, recipient.email)
      suppress(recipient)
      return false
    end
    allowed = @decision.call(recipient)[:allowed]
    return true if allowed && @campaign.sending?

    release_claim(recipient, allowed)
  end

  def release_claim(recipient, allowed)
    # This claim has demonstrably not reached a provider.
    next_status = @campaign.terminal? ? :suppressed : :pending
    recipient.update_columns( # rubocop:disable Rails/SkipsModelValidations
      status: EmailCampaignRecipient.statuses.fetch(next_status.to_s), updated_at: Time.current
    )
    @decision.pause!(@campaign) unless allowed
    false
  end

  def suppress(recipient)
    EmailCampaignRecipient.where(id: recipient.id, status: %i[pending sent]).update_all( # rubocop:disable Rails/SkipsModelValidations
      status: EmailCampaignRecipient.statuses[:suppressed], updated_at: Time.current
    )
    :suppressed
  end
end
