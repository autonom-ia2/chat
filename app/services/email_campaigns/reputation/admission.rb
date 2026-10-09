class EmailCampaigns::Reputation::Admission
  def initialize(campaign)
    @campaign = campaign
  end

  def park_if_blocked!
    protection = EmailCampaigns::Guardrail.protection(@campaign.account, delivery_mode: @campaign.delivery_mode)
    return false unless protection

    park!(protection)
    true
  rescue CustomExceptions::EmailReputationConfiguration
    park!(kind: 'technical', code: 'reputation_configuration_invalid', overridable: false)
    true
  end

  # Local point reads and a conditional claim only; no metrics aggregation, DNS or HTTP.
  # A call already admitted before a later persisted block is an in-flight call.
  # Conditional claims/parking are atomic transitions, not user attribute updates.
  # rubocop:disable Rails/SkipsModelValidations
  def claim!(recipient)
    Account.find(@campaign.account_id).with_lock do
      state = EmailReputationState.find_by(account_id: @campaign.account_id)
      state&.lock!
      @campaign.with_lock do
        next false unless @campaign.sending?
        next false if park_if_blocked!

        claimed = claim_unsuppressed!(recipient)
        consume_override!(state) if claimed && state&.override_active?
        claimed
      end
    end
  end

  def park!(protection)
    EmailCampaign.where(id: @campaign.id, status: %i[sending scheduled paused])
                 .update_all(status: EmailCampaign.statuses[:paused], pause_reason: protection,
                             last_error: protection.fetch(:code), updated_at: Time.current)
  end

  # rubocop:enable Rails/SkipsModelValidations

  private

  # rubocop:disable Rails/SkipsModelValidations -- conditional, tenant-scoped recipient transitions
  def claim_unsuppressed!(recipient)
    pending = EmailCampaignRecipient.where(id: recipient.id, email_campaign_id: @campaign.id, status: :pending)
    if EmailSuppression.uncached { EmailSuppression.suppressed?(@campaign.account, recipient.email) }
      pending.update_all(status: EmailCampaignRecipient.statuses[:suppressed], updated_at: Time.current)
      return false
    end

    pending.update_all(status: EmailCampaignRecipient.statuses[:sent], updated_at: Time.current).positive?
  end
  # rubocop:enable Rails/SkipsModelValidations

  def consume_override!(state)
    remaining = state.override.fetch('remaining') - 1
    state.update!(override: state.override.merge('remaining' => remaining))
    return unless remaining.zero?

    EmailReputationAudit.create!(account_id: @campaign.account_id, action: 'override_budget_exhausted',
                                 actor_id: state.override.fetch('actor_id'), snapshot: { override: state.override })
  end
end
