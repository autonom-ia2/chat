# Formato de `brand_kits.appearance` (#1076). Leitor tolerante, escritor estrito (lição do Bio): chaves
# desconhecidas somem em `to_h`, em qualquer nível; o que fica é validado em `errors`, campo a campo.
#
#   palettes:     { light: {...}, dark: {...} } — as duas versões de cores do e-mail (EmailPalettes::ROLES,
#                 todas '#rrggbb'); cada e-mail escolhe uma. `band` é a faixa do topo, onde fica a logo.
#   site_palette: { primary accent ink muted surface background tint } — as cores achadas no site ('#rrggbb'
#                 ou nil); dão as "cores sugeridas" de volta.
#   typography:   { heading_font, body_font, google_font_url (só https://fonts.googleapis.com), fallback }
#   logo_url:     http(s) ou nil (reserva quando não há logo guardada no ActiveStorage)
#   social_links: [{ network, url }] — rede da lista e link do domínio dela, uma vez cada
#   footer:       { company_name, address, phone, website }
#
# Kits gravados antes das duas versões têm só `palette` (as cores do site): ela vira `site_palette` e as
# duas versões são derivadas dela. Versão ausente também é derivada das cores do site.
class BrandKits::Appearance
  SITE_ROLES = %w[primary accent ink muted surface background tint].freeze
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
    site = site_palette
    {
      'palettes' => palettes(site),
      'site_palette' => site,
      'typography' => typography,
      'logo_url' => text(@raw['logo_url']),
      'social_links' => social_links,
      'footer' => FOOTER_LIMITS.keys.index_with { |key| text(section('footer')[key]) }
    }
  end

  def validate
    palette_errors + typography_errors + logo_errors + social_errors + footer_errors
  end

  # Sem link do Google Fonts (a pessoa trocou a fonte), o link sai do catálogo quando a família está nele.
  def typography
    fonts = TYPOGRAPHY_KEYS.index_with { |key| text(section('typography')[key]) }
    fonts['google_font_url'] ||= BrandKits::GoogleFonts.url_for(fonts.values_at('heading_font', 'body_font').compact)
    fonts.merge('fallback' => FALLBACK_FONT_STACK)
  end

  # Cores do site: as de `site_palette`, ou as do formato antigo `palette`.
  def site_palette
    raw = section('site_palette').presence || section('palette')
    SITE_ROLES.index_with { |role| text(raw[role])&.downcase }
  end

  def palettes(site)
    given = section('palettes')
    derived = nil
    BrandKits::EmailPalettes::MODES.index_with do |mode|
      colors = hash_of(given[mode])
      next (derived ||= BrandKits::EmailPalettes.from_site(site))[mode] if colors.empty?

      BrandKits::EmailPalettes::ROLES.index_with { |role| text(colors[role])&.downcase }
    end
  end

  def palette_errors
    version_errors = @normalized['palettes'].flat_map do |mode, colors|
      colors.reject { |_role, hex| BrandKits::Color.hex?(hex) }.keys.map { |role| "palettes.#{mode}.#{role}" }
    end
    site_errors = @normalized['site_palette'].reject { |_role, hex| hex.nil? || BrandKits::Color.hex?(hex) }.keys
    version_errors + site_errors.map { |role| "site_palette.#{role}" }
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
