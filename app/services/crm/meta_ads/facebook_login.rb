# "Entrar com Facebook" nos Anúncios da Meta (#1069): o cliente entra pelo Login do Facebook para Empresas,
# concede ads_read às contas de anúncios que escolher e a Meta devolve um código. Aqui o código vira token.
#
# A configuração do Login do Facebook para Empresas fica no mesmo app da Meta do cadastro do WhatsApp
# (WHATSAPP_APP_ID e WHATSAPP_APP_SECRET); só o ID da configuração é próprio dos anúncios
# (META_ADS_LOGIN_CONFIGURATION_ID, no Super Admin). Sem os três, o botão não aparece.
#
# O segredo do app vai só para a Meta; o token só sai daqui como valor de retorno. Nenhum dos dois entra em
# log, erro ou payload: a falha registra o código da Meta e a mensagem já limpa.
class Crm::MetaAds::FacebookLogin
  class Error < StandardError
    attr_reader :code

    def initialize(code)
      @code = code
      super(code)
    end
  end

  CONFIGURATION_ID_KEY = 'META_ADS_LOGIN_CONFIGURATION_ID'.freeze
  APP_ID_KEY = 'WHATSAPP_APP_ID'.freeze
  APP_SECRET_KEY = 'WHATSAPP_APP_SECRET'.freeze
  TIMEOUT_SECONDS = 8
  # Recusas que não dizem nada sobre o código: limite de uso e falha passageira da Meta (como no
  # Meta::AdsGraphClient). Viram "a Meta não respondeu", não "o Facebook não confirmou a entrada".
  TRANSIENT_ERROR_CODES = [1, 2, 4, 17, 32, 341, 613].freeze
  TOO_MANY_REQUESTS = 429

  class << self
    def configuration_id
      GlobalConfigService.load(CONFIGURATION_ID_KEY, nil).to_s.strip.presence
    end

    def app_id
      GlobalConfigService.load(APP_ID_KEY, nil).to_s.strip.presence
    end

    def available?
      configuration_id.present? && app_id.present? && app_secret.present?
    end

    # O que a tela precisa para abrir o login da Meta. O ID do app e o da configuração não são segredo.
    def public_payload
      return { available: false } unless available?

      { available: true, app_id: app_id, configuration_id: configuration_id, api_version: api_version }
    end

    def app_secret
      GlobalConfigService.load(APP_SECRET_KEY, nil).to_s.strip.presence
    end

    def api_version
      GlobalConfigService.load('WHATSAPP_API_VERSION', Meta::ConversionsApiClient::DEFAULT_API_VERSION)
    end
  end

  # Código do login → token. Erros: `login_unavailable` (sem configuração), `meta_unavailable` (rede, 5xx,
  # limite) e `login_failed` (código recusado: vencido, já usado ou de outro app).
  def exchange!(code)
    raise Error, 'login_unavailable' unless self.class.available?

    response = request(code)
    body = parse(response.body).to_h
    token = body['access_token'].to_s.presence if response.success?
    return token if token

    refuse!(response.code.to_i, body['error'].to_h)
  end

  private

  def request(code)
    HTTParty.get(token_url, query: token_query(code), timeout: TIMEOUT_SECONDS)
  rescue StandardError => e
    Rails.logger.warn("[MetaAdsLogin] exchange network_error=#{e.class}")
    raise Error, 'meta_unavailable'
  end

  def refuse!(http_code, error)
    log_failure(http_code, error)
    raise Error, transient?(http_code, error['code']) ? 'meta_unavailable' : 'login_failed'
  end

  def token_url
    "#{Meta::ConversionsApiClient::BASE_URI}/#{self.class.api_version}/oauth/access_token"
  end

  def token_query(code)
    { client_id: self.class.app_id, client_secret: self.class.app_secret, code: code }
  end

  def transient?(http_code, error_code)
    http_code >= 500 || http_code == TOO_MANY_REQUESTS || TRANSIENT_ERROR_CODES.include?(error_code)
  end

  def log_failure(http_code, error)
    message = error['message'].to_s.gsub(Meta::ConversionsApiClient::SENSITIVE_PATTERN, '<REDACTED>')
    Rails.logger.warn("[MetaAdsLogin] exchange http=#{http_code.inspect} code=#{error['code'].inspect} message=#{message}")
  end

  def parse(text)
    parsed = JSON.parse(text.to_s)
    parsed.is_a?(Hash) ? parsed : nil
  rescue JSON::ParserError
    nil
  end
end
