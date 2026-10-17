# O catálogo de produtos conectado à WABA de UMA caixa do WhatsApp oficial (#1418, épico #1320), para a Nova campanha
# escolher os produtos e para o disparo conferir que eles seguem à venda.
#
# Isolamento entre clientes, como o `MetaClient`: a WABA é SEMPRE a gravada na caixa e o token é o da caixa, sempre no
# header (nunca na URL nem no texto de erro). Nada aqui aceita WABA nem catálogo vindos do pedido.
#
# Fonte oficial, lida em 14/10/2026:
#   GET /{waba}/product_catalogs — developers.facebook.com/docs/graph-api/reference/whatsapp-business-account/product_catalogs/
#   GET /{catalog}/products (filter, return_only_approved_products, cursores) —
#     developers.facebook.com/docs/marketing-api/reference/product-catalog/products/
# Uma WABA tem um catálogo só (catalogs/upload-inventory). Teste só de leitura na conta 16 (14/10/2026): o token tem
# `catalog_management`; a WABA não tinha catálogo conectado.
class Whatsapp::Templates::CatalogClient
  include Whatsapp::Templates::GraphErrors

  # A WABA da caixa não tem catálogo conectado.
  class NoCatalog < StandardError; end

  Catalog = Data.define(:id, :name, :product_count)
  # sale_price: o preço de promoção que o cliente vê agora; '' sem promoção ou fora do período dela (#1716).
  Product = Data.define(:id, :name, :price, :sale_price, :image_url, :available)
  Page = Data.define(:products, :after)

  REQUEST_TIMEOUT = 10
  PAGE_SIZE = 50
  FIND_LIMIT = 100
  CATALOG_TTL = 5.minutes
  PRODUCT_FIELDS = 'retailer_id,name,price,sale_price,sale_price_start_date,sale_price_end_date,image_url,availability'.freeze
  # Vendável: `availability` da Meta (enum: in stock, out of stock, preorder, available for order, discontinued, pending,
  # mark_as_sold, mark_as_expired — developers.facebook.com/docs/marketing-api/reference/product-item/, lido em
  # 15/10/2026). Encomenda e pré-venda também se compram; o resto fica de fora.
  SELLABLE = ['in stock', 'available for order', 'preorder'].freeze
  # Promoção (#1716): o catálogo guarda o período em `sale_price_effective_date` (dois horários ISO-8601, "início/fim";
  # sem ele, a promoção vale até ser tirada — developers.facebook.com/docs/commerce-platform/catalog/fields/, página
  # atualizada em 05/10/2026, lida em 16/10/2026). A Graph devolve o período em `sale_price_start_date` e
  # `sale_price_end_date` (developers.facebook.com/docs/marketing-api/reference/product-item/, lida em 16/10/2026).
  # Fora do período, o cliente vê o preço cheio; data que não se lê também deixa o preço cheio (nunca promete promoção).

  # timeout/insistir: a foto do envio (#1717) pergunta com prazo curto e uma tentativa só, para não segurar o envio.
  def initialize(inbox:, timeout: REQUEST_TIMEOUT, insistir: true)
    raise Whatsapp::Templates::MetaClient::Unsupported unless Whatsapp::Templates::MetaClient.supported?(inbox)

    @inbox = inbox
    @timeout = timeout
    @insistir = insistir
  end

  # O catálogo da WABA da caixa, ou nil. Guardado por alguns minutos para a tela; o disparo pede `fresh: true`.
  def catalog(fresh: false)
    cached = Rails.cache.fetch(cache_key, expires_in: CATALOG_TTL, force: fresh) { { 'value' => read_catalog } }
    cached['value'] && Catalog.new(**cached['value'].symbolize_keys)
  end

  # Uma página dos produtos aprovados, pelo nome quando há busca.
  def products(search: nil, after: nil)
    query = { fields: PRODUCT_FIELDS, limit: PAGE_SIZE, return_only_approved_products: true }
    query[:filter] = { name: { i_contains: search.to_s.strip } }.to_json if search.to_s.strip.present?
    query[:after] = after if after.present?
    body = get("#{catalog_id!}/products", query)
    Page.new(products: items(body), after: body['paging'].to_h['next'].present? ? body.dig('paging', 'cursors', 'after') : nil)
  end

  # Os produtos aprovados, pelo código (retailer_id), para conferir no disparo: o que não volta não está aprovado ou
  # saiu do catálogo. { código => Product }.
  # catalog_id: o catálogo já conhecido (a foto do envio, #1717) poupa a leitura do catálogo da WABA.
  def find(ids, catalog_id: nil)
    filter = { retailer_id: { is_any: Array(ids).map(&:to_s) } }.to_json
    query = { fields: PRODUCT_FIELDS, limit: FIND_LIMIT, filter: filter, return_only_approved_products: true }
    items(get("#{catalog_id || catalog_id!}/products", query)).index_by(&:id)
  end

  private

  def channel
    @inbox.channel
  end

  def account
    @inbox.account
  end

  def catalog_id!
    catalog&.id || raise(NoCatalog)
  end

  def read_catalog
    item = Array(get("#{channel.waba_id}/product_catalogs", { fields: 'id,name,product_count' })['data']).find { |row| row.is_a?(Hash) }
    item && { 'id' => item['id'].to_s, 'name' => item['name'].to_s, 'product_count' => item['product_count'].to_i }
  end

  def items(body)
    Array(body['data']).select { |row| row.is_a?(Hash) && row['retailer_id'].present? }.map do |row|
      Product.new(id: row['retailer_id'].to_s, name: row['name'].to_s, price: row['price'].to_s, sale_price: sale_price(row),
                  image_url: row['image_url'].to_s, available: SELLABLE.include?(row['availability'].to_s.strip.downcase))
    end
  end

  def sale_price(row)
    price = row['sale_price'].to_s.strip
    price.present? && on_sale?(row, Time.current) ? price : ''
  end

  def on_sale?(row, now)
    start = sale_date(row['sale_price_start_date'])
    finish = sale_date(row['sale_price_end_date'], last_moment: true)
    return false if [start, finish].include?(:unreadable)

    (start.nil? || now >= start) && (finish.nil? || now <= finish)
  end

  # nil sem data (sem limite); :unreadable quando a data não se lê. O fim só com o dia vale o dia inteiro.
  def sale_date(value, last_moment: false)
    text = value.to_s.strip
    return if text.empty?

    time = Time.zone.parse(text)
    return :unreadable unless time

    last_moment && text.exclude?('T') ? time.end_of_day : time
  rescue ArgumentError
    :unreadable
  end

  def get(path, query)
    return request(path, query) unless @insistir

    with_retry { request(path, query) }
  end

  def request(path, query)
    response = HTTParty.get(graph_url(path), query: query, headers: headers, timeout: @timeout)
    return payload(response) if response.success?

    retry_later!(response)
    fail_with(response)
  end

  def cache_key
    "whatsapp:catalog:inbox:#{@inbox.id}:waba:#{channel.waba_id}"
  end

  def graph_url(path)
    "#{ENV.fetch('WHATSAPP_CLOUD_BASE_URL', 'https://graph.facebook.com')}/#{Whatsapp::Templates::MetaClient.api_version}/#{path}"
  end

  def headers
    { 'Authorization' => "Bearer #{channel.template_access_token}" }
  end
end
