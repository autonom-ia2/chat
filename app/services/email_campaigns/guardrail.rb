class EmailCampaigns::Guardrail
  WINDOW = 7.days
  FLAG_KEY = EmailCampaigns::Reputation::Evaluator::FLAG_KEY

  class << self
    def evaluate!(account)
      EmailCampaigns::Reputation::Evaluator.new(account).evaluate![:blocked]
    end

    def reevaluate!(account, delivery_mode: 'ses')
      result = EmailCampaigns::Reputation::Evaluator.new(account).evaluate!
      provider = EmailCampaigns::Reputation::ProviderGate.protection if delivery_mode.to_s == 'ses'
      result.merge(protection: provider || result[:protection] || protection(account, delivery_mode: delivery_mode),
                   resume_allowed: result[:resume_allowed] && provider.nil?)
    end

    # Compatibility: tenant protection only, including the pre-migration legacy flag.
    # DirectInbox intentionally shares tenant protection, but never the SES provider breaker.
    def paused?(account)
      protection(account, delivery_mode: 'direct_inbox').present?
    end

    def resume!(account, actor: nil, delivery_mode: 'ses', &)
      EmailCampaigns::Reputation::Evaluator.new(account).resume!(actor: actor, delivery_mode: delivery_mode, &)
    end

    def protection(account, delivery_mode: 'ses')
      EmailCampaigns::Reputation::Policy.new # Validate configuration even before the first evaluation.
      ActiveRecord::Base.uncached do
        if delivery_mode.to_s == 'ses'
          provider = EmailCampaigns::Reputation::ProviderGate.protection
          return provider if provider
        end
        tenant_protection(account)
      end
    end

    private

    def tenant_protection(account)
      state = EmailReputationState.find_by(account_id: account.id)
      legacy = Account.where(id: account.id).pick(:internal_attributes)&.fetch(FLAG_KEY, nil)
      return if state&.override_active?
      return unless state&.blocked || legacy.present?

      { kind: 'reputation', code: state&.blocked ? 'reputation_paused' : 'legacy_pause',
        triggered_at: state&.triggered_at, overridable: true }
    end
  end
end
