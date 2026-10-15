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
  Product = Data.define(:id, :name, :price, :image_url, :available)
  Page = Data.define(:products, :after)

  REQUEST_TIMEOUT = 10
  PAGE_SIZE = 50
  FIND_LIMIT = 100
  CATALOG_TTL = 5.minutes
  PRODUCT_FIELDS = 'retailer_id,name,price,image_url,availability'.freeze
  # Vendável: `availability` da Meta (enum: in stock, out of stock, preorder, available for order, discontinued, pending,
  # mark_as_sold, mark_as_expired — developers.facebook.com/docs/marketing-api/reference/product-item/, lido em
  # 15/10/2026). Encomenda e pré-venda também se compram; o resto fica de fora.
  SELLABLE = ['in stock', 'available for order', 'preorder'].freeze

  def initialize(inbox:)
    raise Whatsapp::Templates::MetaClient::Unsupported unless Whatsapp::Templates::MetaClient.supported?(inbox)

    @inbox = inbox
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
  def find(ids)
    filter = { retailer_id: { is_any: Array(ids).map(&:to_s) } }.to_json
    query = { fields: PRODUCT_FIELDS, limit: FIND_LIMIT, filter: filter, return_only_approved_products: true }
    items(get("#{catalog_id!}/products", query)).index_by(&:id)
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
      Product.new(id: row['retailer_id'].to_s, name: row['name'].to_s, price: row['price'].to_s, image_url: row['image_url'].to_s,
                  available: SELLABLE.include?(row['availability'].to_s.strip.downcase))
    end
  end

  def get(path, query)
    with_retry do
      response = HTTParty.get(graph_url(path), query: query, headers: headers, timeout: REQUEST_TIMEOUT)
      next payload(response) if response.success?

      retry_later!(response)
      fail_with(response)
    end
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
