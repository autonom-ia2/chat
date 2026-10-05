# Cliente enxuto da Graph API para LER anúncios (#1034): conferir as permissões do token e buscar o
# nome de anúncios, conjuntos e campanhas em lote (`?ids=`).
#
# Mesmas regras do Meta::ConversionsApiClient: o token vai só no header Authorization (nunca na
# query string), a versão da Graph é a mesma do resto da superfície Meta e todo texto que sai daqui
# (corpo, erro) passa pela limpeza de trechos com cara de segredo.
class Meta::AdsGraphClient
  BASE_URI = Meta::ConversionsApiClient::BASE_URI
  TIMEOUT_SECONDS = 8
  # Classes de erro da Graph que mudam a decisão de quem chama:
  # - 190: token inválido ou expirado. Vale para a credencial inteira.
  # - 10 e 200–299: falta permissão. Pode ser o token sem ads_read, mas também um objeto de outra
  #   conta de anúncios a que o token não tem acesso; quem chama confere /me/permissions antes de
  #   condenar a credencial.
  # - 100 e 803: o objeto não existe ou não pode ser lido (anúncio apagado, ID de outra plataforma,
  #   alias inexistente no `?ids=`). Erro daquele ID, não da conta.
  # Qualquer outro (limite de taxa 4/17/32/613/80000+, 5xx, falha de rede) é indisponibilidade
  # passageira: não diz nada sobre o token nem sobre o objeto.
  TOKEN_INVALID_CODE = 190
  SCOPE_ERROR_CODES = ([10] + (200..299).to_a).freeze
  OBJECT_ERROR_CODES = [100, 803].freeze
  ADS_READ = 'ads_read'.freeze
  GRANTED = 'granted'.freeze

  Result = Struct.new(:ok, :http_code, :data, :error_code, :error_message, keyword_init: true) do
    def token_invalid?
      error_code == TOKEN_INVALID_CODE
    end

    def scope_error?
      SCOPE_ERROR_CODES.include?(error_code)
    end

    def object_error?
      OBJECT_ERROR_CODES.include?(error_code)
    end

    def network_error?
      http_code.nil?
    end

    # Falha passageira que não diz nada sobre o token: rede, 5xx ou qualquer código que não seja de
    # token, de permissão nem de objeto (limite de taxa 4/17/32/613/80000+ cai aqui).
    def transient?
      return false if ok
      return true if network_error? || http_code.to_i >= 500

      !(token_invalid? || scope_error? || object_error?)
    end
  end

  # Corpo de /me/permissions: true quando `ads_read` está concedida.
  def self.ads_read_granted?(data)
    Array(data.to_h['data']).any? do |entry|
      entry.is_a?(Hash) && entry['permission'] == ADS_READ && entry['status'] == GRANTED
    end
  end

  def initialize(access_token:, api_version: nil)
    @access_token = access_token
    @api_version = api_version.presence || GlobalConfigService.load('WHATSAPP_API_VERSION', Meta::ConversionsApiClient::DEFAULT_API_VERSION)
  end

  # GET /me/permissions → { data: [{ permission:, status: }] }
  def permissions
    get('me/permissions')
  end

  # GET /me/adaccounts?limit=1 → { data: [{ id }] }. Lista vazia: o token tem ads_read, mas nenhuma
  # conta de anúncios foi atribuída ao usuário do sistema, e nenhum nome poderá ser lido.
  def ad_accounts_sample
    get('me/adaccounts', limit: 1, fields: 'id')
  end

  # GET /?ids=a,b&fields=... → { "<id>" => { "id", "name", ... } }
  def objects(ids, fields:)
    get('', ids: Array(ids).join(','), fields: fields)
  end

  private

  def get(path, query = {})
    response = HTTParty.get(
      "#{BASE_URI}/#{@api_version}/#{path}",
      headers: { 'Authorization' => "Bearer #{@access_token}" },
      query: query.presence,
      timeout: TIMEOUT_SECONDS
    )
    build_result(response)
  rescue StandardError => e
    Result.new(ok: false, http_code: nil, data: nil, error_code: nil, error_message: sanitize(e.message))
  end

  def build_result(response)
    body = parse(response.body)
    return Result.new(ok: true, http_code: response.code, data: body) if response.success? && body.is_a?(Hash)

    error = body.is_a?(Hash) ? body['error'].to_h : {}
    Result.new(ok: false, http_code: response.code, data: nil, error_code: error['code'],
               error_message: sanitize(error['message'].presence || "HTTP #{response.code}"))
  end

  def parse(text)
    JSON.parse(text.to_s)
  rescue JSON::ParserError
    nil
  end

  def sanitize(text)
    return if text.nil?

    text.to_s.gsub(Meta::ConversionsApiClient::SENSITIVE_PATTERN, '<REDACTED>')
  end
end
