# Produtos do catálogo da WABA na campanha (#1418, épico #1320): um produto (SPM), vários (MPM) e carrossel de produtos.
# Lidos da estrutura de `components` (esquema da Meta), nunca do texto.
#
# O que a campanha guarda em `processed_params['products']`:
#   retailer_ids — os códigos dos produtos (retailer_id da Meta), na ordem escolhida;
#   names        — { código => nome } só para dizer qual produto acabou quando a campanha para;
#   catalog_id   — NUNCA vem da tela: o disparo põe o catálogo conectado à WABA da caixa (`DispatchProducts`).
#
# Formato e limites da Meta, lidos em 14/10/2026 (developers.facebook.com/documentation/business-messaging/whatsapp/
# catalogs/{spm,mpm,product-card-carousel}-template-messages):
#   um        — topo PRODUCT e botão SPM; no envio, o topo leva product_retailer_id e catalog_id;
#   varios    — botão MPM; no envio, thumbnail_product_retailer_id e seções (título de até 24 letras), até 30 produtos;
#   carrossel — cartões com topo PRODUCT; aprovado com 2 cartões, manda de 2 a 10, um card_index por produto.
# O título da seção é fixo (decisão do Rodrigo, 14/10/2026): "Escolhidos para você", no idioma do modelo.
module Whatsapp::Templates::ProductParams
  Invalid = Whatsapp::Templates::HeaderMedia::Invalid
  LIMITS = { 'um' => 1..1, 'varios' => 1..30, 'carrossel' => 2..10 }.freeze
  SECTION_TITLES = { 'pt' => 'Escolhidos para você', 'es' => 'Elegidos para ti', 'en' => 'Picked for you' }.freeze
  DEFAULT_SECTION_LANGUAGE = 'en'.freeze
  EMPTY = { header: [], after_body: [], buttons: [] }.freeze

  module_function

  def kind(template)
    components = hashes(template.is_a?(Hash) ? template['components'] : nil)
    types = button_types(components)
    return 'varios' if types.include?('MPM')
    return 'um' if types.include?('SPM')

    'carrossel' if product_cards?(components)
  end

  def product_cards?(components)
    cards = hashes(component(components, 'CAROUSEL')&.dig('cards'))
    cards.any? && cards.all? { |card| product_header?(card) }
  end

  def retailer_ids(processed)
    products = processed.is_a?(Hash) && processed['products'].is_a?(Hash) ? processed['products'] : {}
    Array(products['retailer_ids']).map { |id| id.to_s.strip }.reject(&:empty?).uniq
  end

  def ready?(template, processed)
    limits = LIMITS[kind(template)]
    limits.present? && limits.cover?(retailer_ids(processed).size)
  end

  def normalize!(processed, template)
    processed = processed.to_h
    return processed.except('products') unless kind(template)

    ids = retailer_ids(processed)
    raise Invalid, 'products_required' if ids.empty?
    raise Invalid, 'products_count' unless LIMITS[kind(template)].cover?(ids.size)

    names = processed.dig('products', 'names')
    names = names.is_a?(Hash) ? names.transform_keys(&:to_s) : {}
    processed.merge('products' => { 'retailer_ids' => ids, 'names' => ids.index_with { |id| names[id].to_s }.compact_blank })
  end

  # Os componentes que o envio acrescenta: `header` (antes do corpo), `after_body` (o carrossel) e `buttons` (no fim).
  def components(template, processed)
    ids = retailer_ids(processed)
    return EMPTY if ids.empty?

    catalog = processed.dig('products', 'catalog_id').to_s.presence
    case kind(template)
    when 'um' then EMPTY.merge(header: [{ type: 'header', parameters: [product(ids.first, catalog)] }])
    when 'varios' then EMPTY.merge(buttons: [mpm_button(template, ids)])
    when 'carrossel' then EMPTY.merge(after_body: [carousel(ids, catalog)])
    else EMPTY
    end
  end

  def product(id, catalog)
    { type: 'product', product: { product_retailer_id: id, catalog_id: catalog }.compact }
  end

  def mpm_button(template, ids)
    section = { title: section_title(template), product_items: ids.map { |id| { product_retailer_id: id } } }
    { type: 'button', sub_type: 'mpm', index: mpm_index(template),
      parameters: [{ type: 'action', action: { thumbnail_product_retailer_id: ids.first, sections: [section] } }] }
  end

  def carousel(ids, catalog)
    cards = ids.each_with_index.map do |id, index|
      { card_index: index, components: [{ type: 'header', parameters: [product(id, catalog)] }] }
    end
    { type: 'carousel', cards: cards }
  end

  def section_title(template)
    language = template['language'].to_s.split('_').first.to_s.downcase
    SECTION_TITLES.fetch(language, SECTION_TITLES[DEFAULT_SECTION_LANGUAGE])
  end

  def mpm_index(template)
    button_types(hashes(template['components'])).index('MPM') || 0
  end

  def product_header?(card)
    header = component(hashes(card['components']), 'HEADER')
    header.present? && header['format'].to_s.casecmp?('PRODUCT')
  end

  def button_types(components)
    hashes(component(components, 'BUTTONS')&.dig('buttons')).map { |button| button['type'].to_s.upcase }
  end

  def component(components, type)
    components.find { |item| item['type'].to_s.casecmp?(type) }
  end

  def hashes(list)
    Array(list).select { |item| item.is_a?(Hash) }
  end
end
