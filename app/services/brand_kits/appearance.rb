# Formato de `brand_kits.appearance` (#1076). Leitor tolerante, escritor estrito (lição do Bio): chaves
# desconhecidas somem em `to_h`, em qualquer nível; o que fica é validado em `errors`, campo a campo.
#
#   palette:      { primary accent ink muted surface background tint } — todas '#rrggbb'
#   typography:   { heading_font, body_font, google_font_url (só https://fonts.googleapis.com), fallback }
#   logo_url:     http(s) ou nil (reserva quando não há logo guardada no ActiveStorage)
#   social_links: [{ network, url }] — rede da lista e link do domínio dela, uma vez cada
#   footer:       { company_name, address, phone, website }
class BrandKits::Appearance
  PALETTE_ROLES = %w[primary accent ink muted surface background tint].freeze
  TYPOGRAPHY_KEYS = %w[heading_font body_font google_font_url].freeze
  FOOTER_LIMITS = { 'company_name' => 120, 'address' => 300, 'phone' => 40, 'website' => BrandKits::WebAddress::MAX_LENGTH }.freeze
  FALLBACK_FONT_STACK = 'Arial, Helvetica, sans-serif'.freeze
  GOOGLE_FONTS_HOST = 'fonts.googleapis.com'.freeze
  FONT_NAME_MAX = 60
  # Caracteres que deixariam o nome da fonte sair de um atributo MJML ou de uma declaração CSS.
  FONT_NAME_FORBIDDEN = %("'`;:{}<>()[]\\/,=&\n\r\t).freeze
  MAX_SOCIAL_LINKS = BrandKits::WebAddress::NETWORKS.size

  attr_reader :errors

  def initialize(raw)
    @raw = hash_of(raw)
    @normalized = normalize
    @errors = validate
  end

  def valid?
    errors.empty?
  end

  def to_h
    @normalized.deep_dup
  end

  private

  def normalize
    {
      'palette' => PALETTE_ROLES.index_with { |role| text(section('palette')[role])&.downcase },
      'typography' => TYPOGRAPHY_KEYS.index_with { |key| text(section('typography')[key]) }.merge('fallback' => FALLBACK_FONT_STACK),
      'logo_url' => text(@raw['logo_url']),
      'social_links' => social_links,
      'footer' => FOOTER_LIMITS.keys.index_with { |key| text(section('footer')[key]) }
    }
  end

  def validate
    palette_errors + typography_errors + logo_errors + social_errors + footer_errors
  end

  def palette_errors
    PALETTE_ROLES.reject { |role| BrandKits::Color.hex?(@normalized['palette'][role]) }.map { |role| "palette.#{role}" }
  end

  def typography_errors
    typography = @normalized['typography']
    errors = %w[heading_font body_font].reject { |key| typography[key].nil? || font_name?(typography[key]) }
    url = typography['google_font_url']
    errors << 'google_font_url' unless url.nil? || google_fonts_url?(url)
    errors.map { |key| "typography.#{key}" }
  end

  def logo_errors
    logo = @normalized['logo_url']
    logo.nil? || BrandKits::WebAddress.http?(logo) ? [] : ['logo_url']
  end

  def social_errors
    seen = Set.new
    @normalized['social_links'].each_with_index.flat_map do |link, index|
      network = link['network']
      errors = []
      errors << "social_links.#{index}.network" unless BrandKits::WebAddress::NETWORKS.include?(network) && seen.add?(network)
      errors << "social_links.#{index}.url" unless BrandKits::WebAddress.network_for(link['url']) == network && network.present?
      errors
    end
  end

  def footer_errors
    footer = @normalized['footer']
    errors = FOOTER_LIMITS.filter_map { |key, limit| key if footer[key].present? && footer[key].length > limit }
    errors << 'website' if footer['website'].present? && !BrandKits::WebAddress.http?(footer['website'])
    errors.uniq.map { |key| "footer.#{key}" }
  end

  def social_links
    links = @raw['social_links']
    return [] unless links.is_a?(Array)

    links.first(MAX_SOCIAL_LINKS + 1).map do |link|
      item = hash_of(link)
      { 'network' => text(item['network'])&.downcase, 'url' => text(item['url']) }
    end
  end

  def font_name?(name)
    name.length <= FONT_NAME_MAX && name.each_char.none? { |char| FONT_NAME_FORBIDDEN.include?(char) }
  end

  def google_fonts_url?(url)
    url.length <= BrandKits::WebAddress::MAX_LENGTH && BrandKits::WebAddress.https_host?(url, GOOGLE_FONTS_HOST) &&
      url.each_char.none? { |char| %("'<> \\).include?(char) }
  end

  def section(key)
    hash_of(@raw[key])
  end

  def text(value)
    return nil unless value.is_a?(String)

    value.strip.presence
  end

  def hash_of(value)
    value = value.to_unsafe_h if value.respond_to?(:to_unsafe_h)
    value.is_a?(Hash) ? value.deep_stringify_keys : {}
  end
end
