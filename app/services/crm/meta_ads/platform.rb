# Credencial da plataforma para ler anúncios no modo `partner` (#1047).
#
# O cliente compartilha a conta de anúncios com o portfólio da plataforma (Hub2You) como parceira; a leitura
# usa o token do usuário do sistema desse portfólio, guardado cifrado em AiProviderCredential('meta_ads') e
# configurado no Super Admin. O ID e o nome do portfólio e o ID do usuário do sistema não são segredo e
# ficam em InstallationConfig.
class Crm::MetaAds::Platform
  PROVIDER = 'meta_ads'.freeze
  BUSINESS_ID_KEY = 'META_ADS_PARTNER_BUSINESS_ID'.freeze
  BUSINESS_NAME_KEY = 'META_ADS_PARTNER_BUSINESS_NAME'.freeze
  SYSTEM_USER_ID_KEY = 'META_ADS_SYSTEM_USER_ID'.freeze
  DEFAULT_BUSINESS_NAME = 'Hub2You'.freeze

  class << self
    def token
      return unless Chatwoot.encryption_configured?

      AiProviderCredential.for(PROVIDER)&.api_key.presence
    end

    def business_id
      GlobalConfigService.load(BUSINESS_ID_KEY, nil).to_s.strip.presence
    end

    def business_name
      GlobalConfigService.load(BUSINESS_NAME_KEY, DEFAULT_BUSINESS_NAME).to_s.strip.presence || DEFAULT_BUSINESS_NAME
    end

    def system_user_id
      GlobalConfigService.load(SYSTEM_USER_ID_KEY, nil).to_s.strip.presence
    end

    def configured?
      token.present? && business_id.present?
    end

    # O que a tela mostra ao cliente para ele compartilhar a conta: nunca o token.
    def public_payload
      { available: configured?, business_id: business_id, business_name: business_name }
    end
  end
end
