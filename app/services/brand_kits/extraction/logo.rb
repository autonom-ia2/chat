# Logo candidata de uma página (#1076), ranqueada como no Bio (`extract.py`): imagem no cabeçalho/menu,
# "logo" no alt/classe/id/src, alt igual ao nome da marca ou ao domínio, posição no topo. Reservas:
# og:image, apple-touch-icon e ícone grande. SVG fica de fora na v1 (só PNG/JPEG/WebP/GIF são guardados).
class BrandKits::Extraction::Logo
  Candidate = Struct.new(:url, :score, :source)

  MAX_IMAGES = 100
  MAX_CANDIDATES = 5
  SCORES = { brand: 60, logo: 50, header: 40, top: 10 }.freeze
  TOP_POSITIONS = 6
  SVG_SUFFIX = '.svg'.freeze
  FALLBACKS = [
    ['meta[property="og:image"]', 'content', 'og_image', 20],
    ['link[rel="apple-touch-icon"]', 'href', 'apple_touch_icon', 10],
    ['link[rel="icon"][sizes="192x192"]', 'href', 'icon', 5]
  ].freeze

  attr_reader :svg_skipped

  def initialize(document, page_uri, brand_name:)
    @document = document
    @page_uri = page_uri
    @brand_keys = [alnum(brand_name), alnum(host_label)].select { |key| key.length >= 3 }.uniq
    @svg_skipped = false
  end

  def candidates
    @candidates ||= (image_candidates + fallback_candidates)
                    .uniq(&:url)
                    .sort_by { |candidate| -candidate.score }
                    .first(MAX_CANDIDATES)
  end

  private

  def image_candidates
    @document.css('img').first(MAX_IMAGES).each_with_index.filter_map do |node, position|
      score = image_score(node, position)
      next if score.zero?

      url = BrandKits::WebAddress.join(@page_uri, unwrap_next_image(node['src']))
      next if url.nil?
      next skip_svg if svg?(url)

      Candidate.new(url, score, 'page_logo')
    end
  end

  def image_score(node, position)
    signals = {
      brand: @brand_keys.any? { |key| alnum(node['alt']).include?(key) },
      logo: logo_hint?(node),
      header: inside_header?(node),
      top: position < TOP_POSITIONS
    }
    return 0 unless signals[:brand] || signals[:logo]

    signals.sum { |signal, present| present ? SCORES[signal] : 0 }
  end

  def logo_hint?(node)
    %w[alt class id src].any? { |attribute| node[attribute].to_s.downcase.include?('logo') } || ancestor_hint?(node)
  end

  def fallback_candidates
    FALLBACKS.filter_map do |selector, attribute, source, score|
      url = BrandKits::WebAddress.join(@page_uri, @document.at_css(selector)&.[](attribute))
      next if url.nil?
      next skip_svg if svg?(url)

      Candidate.new(url, score, source)
    end
  end

  def inside_header?(node)
    node.ancestors.any? { |ancestor| %w[header nav].include?(ancestor.name) }
  end

  def ancestor_hint?(node)
    node.ancestors.first(3).any? { |ancestor| ancestor['class'].to_s.downcase.include?('logo') || ancestor['id'].to_s.downcase.include?('logo') }
  end

  # Next.js serve imagens por /_next/image?url=<original>; a logo é a original.
  def unwrap_next_image(src)
    uri = BrandKits::WebAddress.join(@page_uri, src)
    parsed = uri && URI.parse(uri)
    return src unless parsed&.path == '/_next/image' && parsed.query.present?

    URI.decode_www_form(parsed.query).to_h.fetch('url', src)
  rescue URI::Error, ArgumentError
    src
  end

  def svg?(url)
    URI.parse(url).path.to_s.downcase.end_with?(SVG_SUFFIX)
  rescue URI::Error
    false
  end

  def skip_svg
    @svg_skipped = true
    nil
  end

  def host_label
    labels = @page_uri.host.to_s.downcase.delete_prefix('www.').split('.')
    labels.first.to_s
  end

  def alnum(text)
    text.to_s.downcase.each_char.select { |char| char.between?('a', 'z') || char.between?('0', '9') }.join
  end
end
