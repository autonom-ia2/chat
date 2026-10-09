class EmailCampaigns::Guardrail
  WINDOW = 7.days
  FLAG_KEY = EmailCampaigns::Reputation::Evaluator::FLAG_KEY

  class << self
    # Local evaluation is analytics only; delivery admission is global-provider only.
    def evaluate!(account)
      EmailCampaigns::Reputation::Evaluator.new(account).evaluate!
      false
    end

    def reevaluate!(account, delivery_mode: 'ses')
      result = EmailCampaigns::Reputation::Evaluator.new(account).evaluate!
      provider = provider_protection(delivery_mode)
      result.merge(blocked: false, protection: provider, resume_allowed: provider.nil?)
    end

    # Deprecated tenant latch compatibility. Historical tenant state is diagnostic
    # and can no longer pause DirectInbox or SES delivery.
    def paused?(_account)
      false
    end

    # Preserve lock order: account -> local state -> provider -> campaign (inside yield).
    # No local reputation sample is required to resume a manually/provider-paused campaign.
    def resume!(account, actor: nil, delivery_mode: 'ses')
      result = diagnostic_payload(account)
      locked_account = Account.find(account.id)
      locked_account.with_lock do
        state = EmailReputationState.find_by(account_id: account.id)
        state&.lock!
        retire_tenant_protection!(locked_account, state, actor)
        EmailCampaigns::Reputation::ProviderGate.with_admission_lock(delivery_mode: delivery_mode) do
          provider = provider_protection(delivery_mode)
          if provider
            result = diagnostic_payload(account).merge(resume_allowed: false, protection: provider)
          else
            yield if block_given?
            result = diagnostic_payload(account).merge(blocked: false, override_active: false,
                                                       resume_allowed: true, protection: nil)
          end
        end
      end
      result
    end

    def protection(_account, delivery_mode: 'ses')
      provider_protection(delivery_mode)
    end

    private

    def provider_protection(delivery_mode)
      return unless delivery_mode.to_s == 'ses'

      EmailCampaigns::Reputation::ProviderGate.protection
    end

    def retire_tenant_protection!(account, state, actor)
      legacy = account.internal_attributes[FLAG_KEY].present?
      blocked = state&.blocked || state&.override.present?
      return unless legacy || blocked

      state&.update!(blocked: false, override: {})
      Account.where(id: account.id).update_all("internal_attributes = internal_attributes - 'email_campaigns_paused'") # rubocop:disable Rails/SkipsModelValidations
      EmailReputationAudit.create!(account_id: account.id, actor_id: actor&.id, action: 'tenant_protection_retired',
                                   snapshot: { code: 'tenant_protection_retired', source: 'resume' })
    end

    def diagnostic_payload(account)
      state = EmailReputationState.find_by(account_id: account.id)
      return { blocked: false, override_active: false, resume_allowed: true } unless state

      EmailCampaigns::Reputation::Payload.for_state(state)
    end
  end
end
