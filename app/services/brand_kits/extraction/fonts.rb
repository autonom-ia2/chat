# Fontes de uma página (#1076): a família do texto (<body>) e a dos títulos (<h1>, senão <h2>), com
# var() resolvido. Famílias genéricas, do sistema e as "Fallback"/emoji do next/font não contam.
# O link do Google Fonts vem, nesta ordem, do <link> da página, de um @import nas folhas, ou do catálogo
# (BrandKits::GoogleFonts) quando a família existe lá.
class BrandKits::Extraction::Fonts
  GENERIC_FAMILIES = %w[
    serif sans-serif monospace cursive fantasy system-ui ui-sans-serif ui-serif ui-monospace ui-rounded math emoji
    inherit initial unset revert
  ].freeze
  # Pilha de fonte do sistema operacional: quem começa por ela não tem fonte de marca.
  SYSTEM_STACK = %w[-apple-system blinkmacsystemfont system-ui ui-sans-serif].freeze
  IGNORED_FRAGMENTS = %w[fallback emoji symbol var(].freeze

  Result = Struct.new(:heading_font, :body_font, :google_font_url, :url_source, keyword_init: true)

  def initialize(document, stylesheets, google_font_links:)
    @document = document
    @index = stylesheets
    @google_font_links = google_font_links
  end

  def perform
    body = body_family
    heading = heading_family || body
    link, source = google_font_url(heading, body)
    Result.new(heading_font: heading, body_font: body, google_font_url: link, url_source: source)
  end

  private

  def body_family
    body_node = @document.at_css('body')
    candidates = [body_node && @index.style_for(body_node)['font-family'], @index.root_style('body')['font-family'],
                  @index.root_style('html')['font-family']]
    candidates.lazy.map { |value| first_family(value) }.find(&:itself)
  end

  def heading_family
    %w[h1 h2].lazy.map do |tag|
      node = @document.at_css(tag)
      node && first_family(@index.style_for(node)['font-family'])
    end.find(&:itself)
  end

  def google_font_url(heading, body)
    return [@google_font_links.first[:url], @google_font_links.first[:source]] if @google_font_links.any?

    families = [heading, body].compact.uniq.select { |family| BrandKits::GoogleFonts.include?(family) }
    families.any? ? [BrandKits::GoogleFonts.url_for(families), 'catalog'] : [nil, nil]
  end

  def first_family(value)
    return nil if value.blank?

    families = value.split(',').map { |part| clean(part) }
    return nil if SYSTEM_STACK.include?(families.first.to_s.downcase)

    families.find { |family| usable?(family) }
  end

  def clean(part)
    family = part.strip.delete_prefix('"').delete_suffix('"').delete_prefix("'").delete_suffix("'").strip
    next_font_family(family) || family
  end

  # next/font antigo: '__Inter_a1b2c3' → 'Inter'; '__Open_Sans_a1b2c3' → 'Open Sans'.
  def next_font_family(family)
    return nil unless family.start_with?('__')

    parts = family.delete_prefix('__').split('_')
    parts.length > 1 ? parts[0...-1].join(' ') : nil
  end

  def usable?(family)
    lowered = family.downcase
    family.present? && family.length <= BrandKits::Appearance::FONT_NAME_MAX &&
      GENERIC_FAMILIES.exclude?(lowered) && IGNORED_FRAGMENTS.none? { |fragment| lowered.include?(fragment) } &&
      family.each_char.none? { |char| BrandKits::Appearance::FONT_NAME_FORBIDDEN.include?(char) }
  end
end
