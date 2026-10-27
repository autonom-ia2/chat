# Campos do webhook de Página a que o nosso app está inscrito (#2200).
#
# POST /{page_id}/subscribed_apps SUBSTITUI a lista inteira de campos, e DELETE tira o app da Página. Cada recurso que
# precisa de um campo (Messenger, leads de formulário, comentários) passa por aqui: lê a lista atual, soma ou tira só
# os seus campos e grava a lista inteira. Assim um recurso nunca apaga o campo de outro.
#
# A Página lista todos os apps inscritos, e o POST grava os campos do app DONO do token. Por isso os campos lidos são
# os desse app, com o id tirado do próprio token (GET /app), não de configuração: um id que não fosse o do token faria
# o POST apagar os campos dos outros recursos.
#
# Instagram (login do Instagram) não passa por aqui: lá os campos valem pelo painel do app e o subscribed_apps da conta
# não filtra campo (doc da Meta, Limitations; conferido no #2136).
#
# Vários recursos e várias contas mexem na mesma Página ao mesmo tempo (#2200): GET → junta → POST de dois deles em
# paralelo faria um apagar o campo do outro. Por isso a escrita roda sob uma trava por Página (Redis) e, depois do POST,
# relê a lista: se o campo pedido não ficou (outro processo sem trava, ou a Meta), grava de novo; se ainda não ficar,
# erro passageiro para quem chamou tentar de novo.
#
# Mesmas regras do Meta::ConversionsApiClient: o token vai só no header Authorization e todo texto de erro passa
# pela limpeza de trechos com cara de segredo.
class Crm::MetaAds::PageSubscription
  # `transient?` segue a regra do Meta::AdsGraphClient::Result: rede, resposta ilegível, 5xx e limite de uso são
  # passageiros ("tente de novo"); token inválido (190), falta de permissão (10, 200–299) e objeto inexistente
  # (100, 803) são recusa.
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

  BASE_URI = Meta::ConversionsApiClient::BASE_URI
  TIMEOUT_SECONDS = 8
  LOCK_TTL = 60.seconds # cobre as até 6 chamadas de TIMEOUT_SECONDS de uma escrita
  LOCK_WAIT = 15.seconds
  LOCK_POLL = 0.2
  WRITE_ATTEMPTS = 2
  NETWORK_ERRORS = [Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED, Errno::ECONNRESET,
                    OpenSSL::SSL::SSLError, HTTParty::Error, JSON::ParserError].freeze

  def self.lock_key(page_id)
    "meta:page_subscription:#{page_id}"
  end

  def initialize(page_id:, access_token:, api_version: nil)
    @page_id = page_id
    @access_token = access_token
    @api_version = api_version.presence || GlobalConfigService.load('WHATSAPP_API_VERSION', Meta::ConversionsApiClient::DEFAULT_API_VERSION)
  end

  def fields
    apps = Array(request(:get, subscribed_apps_url)['data'])
    apps.select { |entry| entry['id'].to_s == token_app_id }.flat_map { |entry| Array(entry['subscribed_fields']) }.uniq
  end

  def add!(new_fields)
    change!(present: new_fields, absent: [])
  end

  def remove!(old_fields)
    change!(present: [], absent: old_fields)
  end

  private

  def change!(present:, absent:)
    with_page_lock do
      WRITE_ATTEMPTS.times do
        current = fields
        return if settled?(current, present, absent)

        write((current - absent + present).uniq)
      end
      return if settled?(fields, present, absent)

      raise Error, "subscribed_apps did not keep the change on page #{@page_id}"
    end
  end

  def settled?(current, present, absent)
    (present - current).empty? && !current.intersect?(absent)
  end

  def write(wanted)
    return request(:delete, subscribed_apps_url) if wanted.empty?

    request(:post, subscribed_apps_url, body: { subscribed_fields: wanted.join(',') })
  end

  def with_page_lock
    key = self.class.lock_key(@page_id)
    lock_manager = Redis::LockManager.new
    deadline = Time.current + LOCK_WAIT
    until lock_manager.lock(key, LOCK_TTL.to_i)
      raise Error, "subscribed_apps busy on page #{@page_id}" if Time.current >= deadline

      sleep(LOCK_POLL)
    end

    begin
      yield
    ensure
      lock_manager.unlock(key)
    end
  end

  def token_app_id
    @token_app_id ||= request(:get, "#{BASE_URI}/#{@api_version}/app")['id'].to_s
  end

  def request(verb, url, body: nil)
    response = HTTParty.public_send(verb, url, body: body, headers: { 'Authorization' => "Bearer #{@access_token}" }, timeout: TIMEOUT_SECONDS)
    parsed = response.parsed_response.is_a?(Hash) ? response.parsed_response : {}
    return parsed if response.success?

    raise Error.new(scrub("subscribed_apps #{verb} failed: HTTP #{response.code} #{parsed.dig('error', 'message')}"),
                    code: parsed.dig('error', 'code'), http_code: response.code)
  rescue *NETWORK_ERRORS => e
    raise Error, scrub("subscribed_apps #{verb} failed: #{e.class}")
  end

  def subscribed_apps_url
    "#{BASE_URI}/#{@api_version}/#{@page_id}/subscribed_apps"
  end

  def scrub(text)
    text = text.gsub(@access_token, '[FILTERED]') if @access_token.present?
    text.gsub(Meta::ConversionsApiClient::SENSITIVE_PATTERN, '[FILTERED]')
  end
end
