# Monta a proposta de identidade visual a partir da página e das folhas já baixadas (#1076): nome, logo
# candidata, paleta com papéis, fontes, redes e rodapé — cada campo com origem e confiança — e os avisos
# do que faltou. Não busca nada e não grava nada.
class BrandKits::Proposal
  TITLE_SEPARATORS = [' | ', ' - ', ' – ', ' — ', ' · ', ': '].freeze

  def initialize(document, index, page_uri:, google_font_links:, warnings:)
    @document = document
    @index = index
    @page_uri = page_uri
    @google_font_links = google_font_links
    @warnings = warnings.dup
    @json_ld = BrandKits::Extraction::JsonLd.new(document)
    @name = site_name
  end

  def to_h
    {
      'version' => 2,
      'source_url' => @page_uri.to_s,
      'name' => @name,
      'appearance' => appearance,
      'logo_candidates' => logo.candidates.map { |candidate| { 'url' => candidate.url, 'source' => candidate.source } },
      'fields' => roles.fields.merge(font_fields, footer_fields, logo_fields),
      'warnings' => (@warnings + roles.warnings + missing).uniq
    }
  end

  private

  def appearance
    BrandKits::Appearance.new(
      'palettes' => BrandKits::EmailPalettes.from_site(roles.palette),
      'site_palette' => roles.palette,
      'typography' => { 'heading_font' => fonts.heading_font, 'body_font' => fonts.body_font, 'google_font_url' => fonts.google_font_url },
      'logo_url' => logo.candidates.first&.url,
      'social_links' => socials,
      'footer' => footer.transform_values(&:value)
    ).to_h
  end

  def roles
    @roles ||= begin
      colors = BrandKits::Extraction::Colors.new(@document, @index)
      BrandKits::PaletteRoles.new(background: colors.background, ink: colors.ink, buttons: colors.buttons,
                                  brand: colors.brand, accent_hints: colors.accent_variables)
    end
  end

  def fonts
    @fonts ||= BrandKits::Extraction::Fonts.new(@document, @index, google_font_links: @google_font_links).perform
  end

  def logo
    @logo ||= BrandKits::Extraction::Logo.new(@document, @page_uri, brand_name: @name)
  end

  def socials
    @socials ||= BrandKits::Extraction::SocialLinks.new(@document, same_as: @json_ld.same_as).perform
  end

  def footer
    @footer ||= BrandKits::Extraction::Footer.new(@document, json_ld: @json_ld, company_name: @name, page_uri: @page_uri).perform
  end

  def site_name
    og = @document.at_css('meta[property="og:site_name"]')&.[]('content').to_s.squish.presence
    name = og || @json_ld.name || title_name
    name&.truncate(BrandKit::NAME_MAX)
  end

  def title_name
    title = @document.at_css('title')&.text.to_s.squish
    TITLE_SEPARATORS.each { |separator| title = title.split(separator).first.to_s }
    title.strip.presence
  end

  def font_fields
    fields = {}
    fields['typography.heading_font'] = { 'source' => 'stylesheet', 'confidence' => 'medium' } if fonts.heading_font
    fields['typography.body_font'] = { 'source' => 'stylesheet', 'confidence' => 'medium' } if fonts.body_font
    return fields unless fonts.google_font_url

    confidence = fonts.url_source == 'catalog' ? 'medium' : 'high'
    fields.merge('typography.google_font_url' => { 'source' => fonts.url_source, 'confidence' => confidence })
  end

  def footer_fields
    footer.each_with_object({}) do |(key, field), fields|
      fields["footer.#{key}"] = { 'source' => field.source, 'confidence' => field.confidence } if field.value
    end
  end

  def logo_fields
    best = logo.candidates.first
    return {} if best.nil?

    { 'logo_url' => { 'source' => best.source, 'confidence' => best.source == 'page_logo' ? 'medium' : 'low' } }
  end

  def missing
    font_found = fonts.heading_font || fonts.body_font
    {
      'fonts_not_found' => font_found.nil?,
      'font_not_on_google_fonts' => font_found.present? && fonts.google_font_url.nil?,
      'logo_not_found' => logo.candidates.empty?,
      'svg_logo_skipped' => logo.svg_skipped,
      'social_links_not_found' => socials.empty?,
      'address_not_found' => footer['address'].value.nil?
    }.select { |_warning, present| present }.keys
  end
end
