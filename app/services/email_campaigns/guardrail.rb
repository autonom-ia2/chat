class EmailCampaigns::Guardrail
  WINDOW = 7.days
  FLAG_KEY = EmailCampaigns::Reputation::Evaluator::FLAG_KEY

  class << self
    def evaluate!(account)
      EmailCampaigns::Reputation::Evaluator.new(account).evaluate![:blocked]
    end

    def reevaluate!(account, delivery_mode: 'ses')
      result = EmailCampaigns::Reputation::Evaluator.new(account).evaluate!
      provider = protection(account, delivery_mode: delivery_mode)
      result.merge(protection: provider, resume_allowed: provider.nil?)
    end

    # Historical tenant incidents are diagnostic; only the global provider gates SES.
    def paused?(_account)
      false
    end

    def resume!(account, actor: nil, delivery_mode: 'ses', &)
      EmailCampaigns::Reputation::Evaluator.new(account).resume!(actor: actor, delivery_mode: delivery_mode, &)
    end

    def protection(_account, delivery_mode: 'ses')
      return unless delivery_mode.to_s == 'ses'

      ActiveRecord::Base.uncached { EmailCampaigns::Reputation::ProviderGate.protection }
    end
  end
end
