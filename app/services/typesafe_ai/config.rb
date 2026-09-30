class TypesafeAi::Config
  ENABLED_KEY = 'TYPESAFE_JEV_ENABLED'.freeze
  MODEL_KEY = 'TYPESAFE_JEV_MODEL'.freeze
  DEFAULT_MODEL = 'jev-1.13.0'.freeze

  class << self
    def enabled?
      ActiveModel::Type::Boolean.new.cast(GlobalConfigService.load(ENABLED_KEY, 'false'))
    end

    def model
      GlobalConfigService.load(MODEL_KEY, DEFAULT_MODEL).presence || DEFAULT_MODEL
    end

    def api_key
      return unless Chatwoot.encryption_configured?

      AiProviderCredential.for('typesafe')&.api_key.presence
    end

    def configured?
      api_key.present?
    end
  end
end
