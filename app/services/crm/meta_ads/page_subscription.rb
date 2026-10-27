# Campos do webhook a que o nosso app está inscrito numa Página do Facebook ou numa conta do Instagram (#2200).
#
# POST /{id}/subscribed_apps SUBSTITUI a lista inteira de campos, e DELETE tira o app de vez. Cada recurso que
# precisa de um campo (Messenger, Direct, leads de formulário, comentários) passa por aqui: lê a lista atual, soma
# ou tira só os seus campos e grava a lista inteira. Assim um recurso nunca apaga o campo de outro.
#
# - Página (Login do Facebook): graph.facebook.com, token da Página. A Página lista todos os apps inscritos, então
#   os campos são os do app `app_id`.
# - Instagram (Login do Instagram): graph.instagram.com, token da conta, que só enxerga o próprio app.
#
# Mesmas regras do Meta::ConversionsApiClient: o token vai só no header Authorization e todo texto de erro passa
# pela limpeza de trechos com cara de segredo.
class Crm::MetaAds::PageSubscription
  # `transient?` segue a regra do Meta::AdsGraphClient::Result: rede, 5xx e limite de uso são passageiros ("tente de
  # novo"); token inválido (190), falta de permissão (10, 200–299) e objeto inexistente (100, 803) são recusa.
  class Error < StandardError
    attr_reader :code, :http_code

    def initialize(message, code: nil, http_code: nil)
      @code = code
      @http_code = http_code
      super(message)
    end

    def transient?
      return true if http_code.nil? || http_code.to_i >= 500

      refusal_codes = [Meta::AdsGraphClient::TOKEN_INVALID_CODE, *Meta::AdsGraphClient::SCOPE_ERROR_CODES,
                       *Meta::AdsGraphClient::OBJECT_ERROR_CODES]
      refusal_codes.exclude?(code)
    end
  end

  FACEBOOK_BASE_URI = Meta::ConversionsApiClient::BASE_URI
  INSTAGRAM_BASE_URI = 'https://graph.instagram.com'.freeze
  TIMEOUT_SECONDS = 8

  def self.for_instagram(instagram_id:, access_token:, api_version: nil)
    new(page_id: instagram_id, access_token: access_token, app_id: nil, base_uri: INSTAGRAM_BASE_URI,
        api_version: api_version.presence || GlobalConfigService.load('INSTAGRAM_API_VERSION', 'v22.0'))
  end

  def initialize(page_id:, access_token:, app_id:, api_version: nil, base_uri: FACEBOOK_BASE_URI)
    @node_id = page_id
    @access_token = access_token
    @app_id = app_id&.to_s
    @base_uri = base_uri
    @api_version = api_version.presence || GlobalConfigService.load('WHATSAPP_API_VERSION', Meta::ConversionsApiClient::DEFAULT_API_VERSION)
  end

  def fields
    apps = Array(request(:get)['data'])
    apps = apps.select { |entry| entry['id'].to_s == @app_id } if @app_id
    apps.flat_map { |entry| Array(entry['subscribed_fields']) }.uniq
  end

  def add!(new_fields)
    current = fields
    wanted = (current + new_fields).uniq
    return if wanted == current

    request(:post, body: { subscribed_fields: wanted.join(',') })
  end

  def remove!(old_fields)
    current = fields
    remaining = current - old_fields
    return if remaining == current
    return request(:delete) if remaining.empty?

    request(:post, body: { subscribed_fields: remaining.join(',') })
  end

  private

  def request(verb, body: nil)
    response = HTTParty.public_send(verb, url, body: body, headers: { 'Authorization' => "Bearer #{@access_token}" }, timeout: TIMEOUT_SECONDS)
    parsed = response.parsed_response.is_a?(Hash) ? response.parsed_response : {}
    return parsed if response.success?

    raise Error.new(scrub("subscribed_apps #{verb} failed: HTTP #{response.code} #{parsed.dig('error', 'message')}"),
                    code: parsed.dig('error', 'code'), http_code: response.code)
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED, Errno::ECONNRESET, OpenSSL::SSL::SSLError => e
    raise Error, scrub("subscribed_apps #{verb} failed: #{e.class}")
  end

  def url
    "#{@base_uri}/#{@api_version}/#{@node_id}/subscribed_apps"
  end

  def scrub(text)
    text.gsub(@access_token, '[FILTERED]').gsub(Meta::ConversionsApiClient::SENSITIVE_PATTERN, '[FILTERED]')
  end
end
