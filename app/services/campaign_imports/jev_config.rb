# Jev in the campaign journey (Públicos, #992) has its own switch, separate from
# TYPESAFE_JEV_ENABLED, which keeps governing the email recipient import. The key and model
# stay the TypeSafe ones (TypesafeAi::Config).
class CampaignImports::JevConfig
  ENABLED_KEY = 'CAMPAIGN_JOURNEY_JEV_ENABLED'.freeze

  class << self
    def enabled?
      ActiveModel::Type::Boolean.new.cast(GlobalConfigService.load(ENABLED_KEY, 'false'))
    end

    def available?
      enabled? && TypesafeAi::Config.configured?
    end
  end
end
