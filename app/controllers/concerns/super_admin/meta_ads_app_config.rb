# Anúncios da Meta (#1047) no Super Admin: portfólio parceiro e usuário do sistema da plataforma. Os IDs vão
# para InstallationConfig; o token é só de escrita e vai cifrado para AiProviderCredential('meta_ads').
# META_ADS_LOGIN_CONFIGURATION_ID (#1069): configuração do "Entrar com Facebook", no mesmo app do WhatsApp.
module SuperAdmin::MetaAdsAppConfig
  META_ADS_CONFIGS = %w[
    META_ADS_PARTNER_BUSINESS_ID META_ADS_PARTNER_BUSINESS_NAME META_ADS_SYSTEM_USER_ID META_ADS_PLATFORM_TOKEN
    META_ADS_LOGIN_CONFIGURATION_ID
  ].freeze
  META_ADS_TOKEN_KEY = 'META_ADS_PLATFORM_TOKEN'.freeze

  private

  def prepare_meta_ads_secret
    return unless @config == 'meta_ads'

    @app_config.delete(META_ADS_TOKEN_KEY)
    @meta_ads_secret_configured = AiProviderCredential.for(Crm::MetaAds::Platform::PROVIDER).present?
  end

  # Só grava quando veio preenchido; em branco mantém o token atual.
  def persist_meta_ads_token(errors)
    return unless @config == 'meta_ads'

    token = params.fetch('app_config', {}).fetch(META_ADS_TOKEN_KEY, '').to_s.strip
    return if token.blank?

    provider = Crm::MetaAds::Platform::PROVIDER
    credential = AiProviderCredential.for(provider) || AiProviderCredential.new(provider: provider)
    credential.api_key = token
    errors.concat(credential.errors.full_messages) unless credential.save
  end
end
