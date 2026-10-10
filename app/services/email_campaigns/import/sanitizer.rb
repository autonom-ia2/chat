# Allowlist cleaning of an imported model (#1099), on the parsed tree — never on the markup text. Elements outside
# KEEP are dropped with their content when active or useless in e-mail (script, form, iframe, object, svg, base, meta,
# link, Office XML...) and unwrapped otherwise, keeping their text. Attributes are kept only from an allowlist (no on*,
# no class/id/data-*); inline CSS only for known properties whose value carries no url(), expression(), script scheme
# or escape — background colors included. Position, offsets, indent and clip stay so Visibility can tell off-screen
# and clipped text; the converter never writes them out. A background image (attribute or CSS) becomes the internal
# data-import-bg marker the converter turns into a section background, when it is an http(s) address. Nokogiri and
# string methods — no regex. Active elements and unsafe CSS are the rules shared with the AI path
# (EmailCampaigns::MarkupPolicy, #1104).
class EmailCampaigns::Import::Sanitizer
  UNSAFE = EmailCampaigns::MarkupPolicy::UNSAFE_ELEMENTS
  FORM_PARTS = %w[input button select textarea option optgroup label fieldset legend datalist output].freeze
  SILENT = %w[style head title meta source track xml map area].freeze
  KEEP = %w[html body center table thead tbody tfoot tr td th caption col colgroup div span p a img br hr h1 h2 h3 h4 h5 h6
            strong b em i u s strike del ins small big sup sub font ul ol li blockquote pre code section article header footer
            main aside nav figure figcaption address abbr cite q mark time wbr dl dt dd].freeze
  ATTRIBUTES = %w[style align valign width height bgcolor colspan rowspan dir].freeze
  TAG_ATTRIBUTES = { 'a' => %w[href title], 'img' => %w[src alt title], 'font' => %w[color size face] }.freeze
  INTERNAL = %w[data-import-bg data-import-missing].freeze
  STYLE_PROPERTIES = %w[color background-color font-size font-family font-weight font-style line-height text-align text-decoration
                        text-transform letter-spacing padding padding-top padding-right padding-bottom padding-left border border-top
                        border-right border-bottom border-left border-color border-width border-style border-radius width max-width
                        min-width height max-height display visibility opacity overflow mso-hide vertical-align float position
                        left top text-indent clip].freeze
  HEAD_UNSAFE = 'script, base, iframe, object, embed'.freeze

  def self.call(root, report)
    new(root, report).call
  end

  def initialize(root, report)
    @root = root
    @report = report
  end

  def call
    walk(@root)
    @root
  end

  private

  def walk(node)
    node.element_children.to_a.each { |child| visit(child) }
  end

  def visit(element)
    name = element.name.downcase
    return drop(element, name) if drop?(name)
    return video(element) if name == 'video'

    walk(element)
    KEEP.include?(name) ? clean(element, name) : unwrap(element)
  end

  def drop?(name)
    UNSAFE.include?(name) || FORM_PARTS.include?(name) || SILENT.include?(name) || name.include?(':') || name.start_with?('amp-')
  end

  def drop(element, name)
    if name == 'head'
      count_head(element)
    elsif name.start_with?('amp-')
      @report.add(:embed_removed)
    elsif UNSAFE.include?(name) || FORM_PARTS.include?(name)
      count_unsafe(element, name)
    end
    element.remove
  end

  def count_head(head)
    head.css(HEAD_UNSAFE).each { |node| @report.add(:unsafe_removed, item: node.name) }
    refresh = head.css('meta[http-equiv]').any? { |node| node['http-equiv'].to_s.strip.casecmp?('refresh') }
    @report.add(:unsafe_removed, item: 'meta') if refresh
  end

  # A form (or a loose form control) leaves with its visible labels recorded.
  def count_unsafe(element, name)
    form = name == 'form' || FORM_PARTS.include?(name)
    @report.add(:unsafe_removed, item: form ? 'form' : name)
    @report.drop_text(element.text, :unsafe) if form
  end

  def video(element)
    poster = element['poster'].to_s.strip
    source = (element['src'] || element.at_css('source')&.[]('src')).to_s.strip
    if EmailCampaigns::Import::Url.http?(poster) && EmailCampaigns::Import::Url.http?(source)
      link = element.document.create_element('a', 'href' => source)
      link.add_child(element.document.create_element('img', 'src' => poster, 'alt' => ''))
      element.replace(link)
      return @report.add(:video_as_image)
    end
    @report.add(:embed_removed)
    element.remove
  end

  def unwrap(element)
    element.children.to_a.each { |child| element.add_previous_sibling(child) }
    element.remove
  end

  def clean(element, name)
    background(element)
    allowed = ATTRIBUTES + TAG_ATTRIBUTES.fetch(name, []) + INTERNAL
    element.attribute_nodes.each { |attribute| attribute.remove unless allowed.include?(attribute.name.downcase) }
    style(element)
  end

  def background(element)
    url = element['background'].presence || style_url(element['style'])
    element.remove_attribute('background')
    return if url.blank?

    url = "https:#{EmailCampaigns::Import::Url.clean(url)}" if EmailCampaigns::Import::Url.protocol_relative?(url)
    return @report.add(:unsafe_css_removed) unless EmailCampaigns::Import::Url.http?(url)

    element['data-import-bg'] = EmailCampaigns::Import::Url.clean(url)
  end

  def style_url(style)
    declarations = EmailCampaigns::Import::StyleMap.parse(style)
    declarations.values_at('background-image', 'background').compact.each do |value|
      start = value.downcase.index('url(')
      next if start.nil?

      inside = value[(start + 4)..].to_s
      return inside[0...(inside.index(')') || inside.length)].strip.delete('"\'')
    end
    nil
  end

  def style(element)
    return if element['style'].nil?

    kept = EmailCampaigns::Import::StyleMap.parse(element['style']).each_with_object({}) { |(property, value), out| keep(out, property, value) }
    kept.empty? ? element.remove_attribute('style') : element['style'] = EmailCampaigns::Import::StyleMap.dump(kept)
  end

  # Background images were already taken by #background (background-image leaves here); the shorthand gives only its
  # color. Every other value is checked.
  def keep(out, property, value)
    return shorthand(out, value) if property == 'background'
    return if property == 'background-image'
    return @report.add(:unsafe_css_removed) if unsafe?(value)

    out[property] = value if STYLE_PROPERTIES.include?(property)
  end

  def shorthand(kept, value)
    color = EmailCampaigns::Import::StyleMap.first_color(value)
    kept['background-color'] ||= color if color
  end

  def unsafe?(value)
    EmailCampaigns::MarkupPolicy.unsafe_css?(value)
  end
end
