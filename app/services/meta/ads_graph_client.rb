# Cliente enxuto da Graph API para LER anúncios (#1034): conferir as permissões do token e buscar o
# nome de anúncios, conjuntos e campanhas, um objeto por chamada. O lote `?ids=` foi descontinuado
# na Graph v26.0 e responde com o código 100, que aqui quer dizer "objeto inexistente" (#1043).
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
  #   ID que não é de anúncio). Erro daquele ID, não da conta.
  # Qualquer outro (limite de taxa 4/17/32/613/80000+, 5xx, falha de rede) é indisponibilidade
  # passageira: não diz nada sobre o token nem sobre o objeto.
  TOKEN_INVALID_CODE = 190
  SCOPE_ERROR_CODES = ([10] + (200..299).to_a).freeze
  OBJECT_ERROR_CODES = [100, 803].freeze
  ADS_READ = 'ads_read'.freeze
  GRANTED = 'granted'.freeze

  # Cabeçalhos em que a Meta diz quanto do limite de uso já foi gasto (Crm::MetaAds::Insights::Usage).
  USAGE_HEADERS = %w[x-business-use-case-usage x-fb-ads-insights-throttle x-app-usage].freeze

  Result = Struct.new(:ok, :http_code, :data, :error_code, :error_message, :usage_headers, keyword_init: true) do
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

  # GET /<id>?fields=... → { "id", "name", ... }
  def object(id, fields:)
    get(id.to_s, fields: fields)
  end

  # Conexão guiada (#1047). IDs de conta de anúncios entram sem o prefixo `act_`.
  AD_ACCOUNT_FIELDS = 'id,account_id,name,account_status,currency,timezone_name,business{id,name}'.freeze
  PIXEL_FIELDS = 'id,name,last_fired_time'.freeze
  LIST_LIMIT = 100
  MAX_PAGES = 10

  # Contas que o próprio token enxerga: as do cliente (modo `token`) ou as já atribuídas ao usuário do sistema
  # da plataforma, cujo token é este (modo `partner`).
  def ad_accounts
    paged('me/adaccounts', fields: AD_ACCOUNT_FIELDS)
  end

  # Contas que clientes compartilharam com o portfólio da plataforma como parceira.
  def client_ad_accounts(business_id)
    paged("#{business_id}/client_ad_accounts", fields: AD_ACCOUNT_FIELDS)
  end

  # Dá ao usuário do sistema da plataforma acesso "Ver desempenho" (ANALYZE) numa conta compartilhada.
  def assign_system_user(ad_account_id, system_user_id:, business_id:)
    post("act_#{ad_account_id}/assigned_users", user: system_user_id, tasks: ['ANALYZE'].to_json, business: business_id)
  end

  def ad_account(ad_account_id)
    get("act_#{ad_account_id}", fields: AD_ACCOUNT_FIELDS)
  end

  def spend_last_30d(ad_account_id)
    get("act_#{ad_account_id}/insights", date_preset: 'last_30d', fields: 'spend')
  end

  # Insights de anúncios (#1073). `query` traz level, fields, date_preset etc. Cada página vai para o bloco
  # assim que chega; a primeira falha interrompe e é devolvida (com os cabeçalhos de uso, para quem chama
  # decidir se espera). Sucesso devolve o resultado da última página.
  INSIGHTS_PAGE_LIMIT = 500
  INSIGHTS_MAX_PAGES = 100

  def each_insights_page(ad_account_id, query, &)
    each_page("act_#{ad_account_id}/insights", query.merge(limit: INSIGHTS_PAGE_LIMIT), &)
  end

  # Relatório assíncrono (primeira carga de 90 dias): POST devolve { report_run_id }; o status é lido em
  # GET /<id> e as linhas em GET /<id>/insights, quando `async_status` for "Job Completed".
  def start_insights_report(ad_account_id, query)
    post("act_#{ad_account_id}/insights", query)
  end

  def insights_report_status(report_run_id)
    get(report_run_id.to_s, fields: 'async_status,async_percent_completion')
  end

  def each_report_page(report_run_id, &)
    each_page("#{report_run_id}/insights", { limit: INSIGHTS_PAGE_LIMIT }, &)
  end

  def ad_account_pixels(ad_account_id)
    paged("act_#{ad_account_id}/adspixels", fields: PIXEL_FIELDS)
  end

  private

  def get(path, query = {})
    request(:get, path, query: query.presence)
  end

  # Listas da Graph vêm em páginas: segue o cursor `after` até MAX_PAGES (1.000 itens) e devolve
  # { "data" => [...] } como uma página só. Erro em qualquer página devolve esse erro.
  def paged(path, query)
    rows = []
    result = each_page(path, query.merge(limit: LIST_LIMIT), max_pages: MAX_PAGES) { |page| rows.concat(page) }
    return result unless result.ok

    Result.new(ok: true, http_code: 200, data: { 'data' => rows })
  end

  # Segue o cursor `after` página a página, até max_pages.
  def each_page(path, query, max_pages: INSIGHTS_MAX_PAGES)
    after = nil
    result = nil
    max_pages.times do
      result = get(path, query.merge(after: after).compact)
      return result unless result.ok

      yield Array(result.data.to_h['data'])
      after = result.data.to_h.dig('paging', 'cursors', 'after')
      break if after.blank? || result.data.to_h.dig('paging', 'next').blank?
    end
    result
  end

  def post(path, body)
    request(:post, path, body: body)
  end

  def request(verb, path, **)
    response = HTTParty.public_send(
      verb,
      "#{BASE_URI}/#{@api_version}/#{path}",
      headers: { 'Authorization' => "Bearer #{@access_token}" },
      timeout: TIMEOUT_SECONDS,
      **
    )
    log_failure(verb, path, build_result(response))
  rescue StandardError => e
    log_failure(verb, path, Result.new(ok: false, http_code: nil, data: nil, error_code: nil, error_message: sanitize(e.message)))
  end

  # Toda recusa da Meta fica no log com o caminho, o código e a mensagem já limpa: sem isso, um erro que
  # quem chama trata como "ainda não" vira silêncio em produção (#1068). O token nunca entra no caminho.
  def log_failure(verb, path, result)
    return result if result.ok

    Rails.logger.warn("[MetaAdsGraph] #{verb.to_s.upcase} #{path} http=#{result.http_code.inspect} " \
                      "code=#{result.error_code.inspect} message=#{result.error_message}")
    result
  end

  def build_result(response)
    body = parse(response.body)
    usage = usage_headers(response)
    return Result.new(ok: true, http_code: response.code, data: body, usage_headers: usage) if response.success? && body.is_a?(Hash)

    error = body.is_a?(Hash) ? body['error'].to_h : {}
    Result.new(ok: false, http_code: response.code, data: nil, error_code: error['code'], usage_headers: usage,
               error_message: sanitize(error['message'].presence || "HTTP #{response.code}"))
  end

  def usage_headers(response)
    headers = response.headers
    return {} if headers.blank?

    USAGE_HEADERS.each_with_object({}) do |name, found|
      value = headers[name]
      found[name] = value if value.present?
    end
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
