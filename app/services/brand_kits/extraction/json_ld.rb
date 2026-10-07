# Dados estruturados (JSON-LD) de uma página (#1076): a organização (nome, telefone, site, endereço postal)
# e os perfis em `sameAs`. Blocos malformados são ignorados.
class BrandKits::Extraction::JsonLd
  MAX_BLOCKS = 10
  MAX_BLOCK_BYTES = 200_000
  MAX_NODES = 200
  ORGANIZATION_SUFFIXES = %w[Organization Corporation LocalBusiness Store Restaurant].freeze
  ADDRESS_KEYS = %w[streetAddress addressLocality addressRegion postalCode addressCountry].freeze

  def initialize(document)
    @nodes = parse(document)
  end

  def organization
    @organization ||= @nodes.find { |node| organization?(node) } || {}
  end

  def name
    text(organization['name'])
  end

  def telephone
    text(organization['telephone'])
  end

  def url
    text(organization['url'])
  end

  def address
    value = organization['address']
    value = value.first if value.is_a?(Array)
    return text(value) if value.is_a?(String)

    value.is_a?(Hash) ? postal_address(value) : nil
  end

  def postal_address(value)
    parts = ADDRESS_KEYS.map do |key|
      part = value[key]
      part.is_a?(Hash) ? part['name'] : part
    end
    text(parts.filter_map { |part| text(part) }.join(', '))
  end

  def same_as
    @nodes.flat_map { |node| Array(node['sameAs']) }.grep(String)
  end

  private

  def parse(document)
    blocks = document.css('script[type="application/ld+json"]').first(MAX_BLOCKS)
    nodes = blocks.flat_map do |script|
      content = script.content.to_s
      content.bytesize > MAX_BLOCK_BYTES ? [] : flatten(JSON.parse(content))
    rescue JSON::ParserError
      []
    end
    nodes.first(MAX_NODES)
  end

  def flatten(value)
    case value
    when Array then value.flat_map { |item| flatten(item) }
    when Hash then [value] + flatten(value['@graph'])
    else []
    end
  end

  def organization?(node)
    Array(node['@type']).grep(String).any? { |type| ORGANIZATION_SUFFIXES.any? { |suffix| type.end_with?(suffix) } }
  end

  def text(value)
    value.is_a?(String) ? value.squish.presence : nil
  end
end
