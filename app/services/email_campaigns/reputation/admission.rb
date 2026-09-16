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

  # Both the compatibility API and delivery engines use the same hygiene/claim path.
  def claim!(recipient)
    EmailCampaigns::DeliveryClaim.new(@campaign).claim(recipient) == :claimed
  end

  # Short, shared lock order. Callers only perform local eligibility/claim writes here.
  def with_delivery_locks(recipient)
    with_campaign_locks do |state|
      recipient.with_lock { yield state }
    end
  end

  # Enter before taking any campaign/recipient lock, never from a save callback.
  # with_lock reloads clean objects; callers must assign changes inside this block.
  def with_campaign_locks
    ActiveRecord::Base.uncached do
      Account.find(@campaign.account_id).with_lock do
        state = EmailReputationState.find_by(account_id: @campaign.account_id)
        state&.lock!
        @campaign.with_lock { yield state }
      end
    end
  end

  # rubocop:disable Rails/SkipsModelValidations -- conditional campaign parking
  def park!(protection)
    with_campaign_locks do
      EmailCampaign.where(id: @campaign.id, status: %i[sending scheduled paused])
                   .update_all(status: EmailCampaign.statuses[:paused], pause_reason: protection,
                               last_error: protection.fetch(:code), updated_at: Time.current)
      @campaign.reload
    end
  end

  # rubocop:enable Rails/SkipsModelValidations

  # Called once, inside with_delivery_locks, only after a successful final claim.
  def consume_override!(state)
    remaining = state.override.fetch('remaining') - 1
    state.update!(override: state.override.merge('remaining' => remaining))
    return unless remaining.zero?

    EmailReputationAudit.create!(account_id: @campaign.account_id, action: 'override_budget_exhausted',
                                 actor_id: state.override.fetch('actor_id'), snapshot: { override: state.override })
  end
end
