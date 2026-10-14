require 'uri'

# Lista os proxies do plano da Webshare (API v2, modo direto) — #1516. A chave vem de WEBSHARE_API_KEY e só vai no
# cabeçalho do pedido: nunca em log, mensagem de erro ou inspect. A resposta traz usuário e senha de cada proxy; eles
# ficam só em memória (Webshare::Proxy).
# A conta tem vários planos; cada cliente lista um pool: :isp (Static Residential, proxy_subtype "isp") ou :datacenter
# (Proxy Server, proxy_subtype "default"). WEBSHARE_ISP_PLAN_ID / WEBSHARE_DATACENTER_PLAN_ID fixam o plano; sem elas,
# vale o plano ativo daquele subtipo. O plano "residential" (rotativo, com franquia de banda) nunca serve.
class Webshare::Client
  class Error < StandardError; end

  HOST = 'proxy.webshare.io'.freeze
  LIST_URL = "https://#{HOST}/api/v2/proxy/list/?mode=direct&page_size=100".freeze
  PLANS_URL = "https://#{HOST}/api/v2/subscription/plan/".freeze
  PLAN_SUBTYPES = { isp: 'isp', datacenter: 'default' }.freeze
  PLAN_ID_ENVS = { isp: 'WEBSHARE_ISP_PLAN_ID', datacenter: 'WEBSHARE_DATACENTER_PLAN_ID' }.freeze
  TIMEOUT = 5
  # 20 páginas de 100 = 2.000 IPs: teto para um `next` defeituoso não virar laço.
  MAX_PAGES = 20

  attr_reader :pool

  def initialize(pool: :isp, api_key: ENV.fetch('WEBSHARE_API_KEY', ''), plan_id: nil)
    @pool = pool.to_sym
    raise ArgumentError, "pool desconhecido: #{pool}" unless PLAN_SUBTYPES.key?(@pool)

    @api_key = api_key.to_s.strip
    @plan_id = (plan_id || ENV.fetch(PLAN_ID_ENVS.fetch(@pool), '')).to_s.strip.presence
  end

  def configured?
    @api_key.present?
  end

  def proxies
    raise Error, 'webshare_api_key_missing' unless configured?

    url = "#{LIST_URL}&plan_id=#{URI.encode_www_form_component(plan_id)}"
    results = []
    MAX_PAGES.times do
      page = fetch_page(url)
      results.concat(Array(page['results']))
      url = page['next'].presence
      break if url.nil?
    end
    results.map { |item| Webshare::Proxy.from_api(item) }
  end

  # Plano do pool: o fixado por ENV, ou o ativo do subtipo do pool descoberto na API.
  def plan_id
    @plan_id ||= discover_plan_id
  end

  def inspect
    "#<#{self.class.name} pool=#{@pool} configured=#{configured?}>"
  end

  private

  def discover_plan_id
    subtype = PLAN_SUBTYPES.fetch(@pool)
    plan = Array(fetch_page(PLANS_URL)['results']).find { |item| usable_plan?(item) && item['proxy_subtype'] == subtype }
    raise Error, "webshare_plan_not_found pool=#{@pool}" if plan.nil?

    Rails.logger.info("[whatsapp_proxy] plano da Webshare pool=#{@pool} id=#{plan['id']} subtipo=#{plan['proxy_subtype']}")
    plan['id'].to_s
  end

  # Ativo (quando a API informa o estado) e nunca o residencial rotativo.
  def usable_plan?(plan)
    return false if plan['proxy_type'] == 'residential' || plan['proxy_subtype'] == 'residential'

    plan['status'].nil? || plan['status'] == 'active'
  end

  def fetch_page(url)
    ensure_webshare_url!(url)
    response = HTTParty.get(url, headers: { 'Authorization' => "Token #{@api_key}", 'Accept' => 'application/json' }, timeout: TIMEOUT)
    raise Error, "webshare_list_failed status=#{response.code}" unless response.success?

    body = response.parsed_response
    raise Error, 'webshare_list_unexpected_body' unless body.is_a?(Hash)

    body
  rescue HTTParty::Error, SocketError, Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED, OpenSSL::SSL::SSLError => e
    raise Error, "webshare_list_failed #{e.class}"
  end

  # A chave só segue para a própria Webshare, mesmo que o `next` da paginação aponte para outro lugar.
  def ensure_webshare_url!(url)
    uri = URI.parse(url)
    raise Error, 'webshare_unexpected_next_url' unless uri.scheme == 'https' && uri.host == HOST
  rescue URI::InvalidURIError
    raise Error, 'webshare_unexpected_next_url'
  end
end
