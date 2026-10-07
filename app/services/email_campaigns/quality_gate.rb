# Quality gate for an e-mail design (#1082): checks one MJML source plus its compiled HTML against the rules
# every shared template must meet — strict MJML, only blocks the editor edits, explicit close tags, one locked
# footer with the only unsubscribe link, WCAG AA contrast, 44px buttons, readable sizes in explicit Arial,
# described images served by the installation (<= 200 KB), HTML under Gmail's 102 KB clip, and placeholders
# every campaign can fill. Wired to the seed library (spec/services/email_campaigns/quality_gate_library_spec.rb);
# built to run after AI generation too (EmailCampaigns::Ai::QualityCheck). Parses with Nokogiri and plain string
# methods — no regex.
#
# On the server, without Node (template import, #1099, and the AI jobs, #1095), it runs on the MJML alone: html: nil
# skips the checks that need the compiled HTML and estimates its size (EstimatedSize); remote_images: true accepts
# absolute web images that the import copies afterwards (RemoteImage), still demanding a description; fonts: lets an
# imported model keep a font every e-mail program shows (Import::WebFonts) instead of Arial.
class EmailCampaigns::QualityGate
  include Css

  Violation = Struct.new(:check, :detail)

  EDITABLE_TAGS = %w[
    mjml mj-head mj-title mj-preview mj-attributes mj-all mj-body mj-wrapper mj-section mj-group mj-column
    mj-text mj-image mj-button mj-divider mj-spacer mj-social mj-social-element
  ].freeze
  INLINE_TAGS = %w[a br strong b em span].freeze
  FONT = 'arial'.freeze
  UNSUBSCRIBE = 'unsubscribe_url'.freeze
  UNSUBSCRIBE_HREF = '{{ unsubscribe_url }}'.freeze
  MIN_BODY_PX = 14
  MIN_FOOTER_PX = 12
  MIN_BUTTON_PX = 44
  MIN_CONTRAST = 4.5
  MIN_LARGE_CONTRAST = 3.0
  LARGE_TEXT_PX = 24
  BOLD = %w[bold 700 800 900].freeze
  MAX_HTML_BYTES = 102 * 1024
  # What an AI adjustment of an e-mail can break (#1095). The others are about how a template is built and served.
  AI_CHECKS = %i[contrast button_height image_alt placeholders unsubscribe html_size].freeze
  # MJML defaults, used when the attribute is absent.
  DEFAULT_FONT_PX = 13
  DEFAULT_TEXT_COLOR = '#000000'.freeze
  DEFAULT_BUTTON_COLOR = '#ffffff'.freeze
  DEFAULT_BUTTON_BACKGROUND = '#414141'.freeze
  DEFAULT_INNER_PADDING = '10px 25px'.freeze
  DEFAULT_BUTTON_LINE_HEIGHT = '120%'.freeze

  def self.locked_footers(mjml)
    footer_sections(Nokogiri::HTML5.fragment(mjml.to_s)).map(&:to_html)
  end

  def self.footer_sections(doc)
    doc.css('mj-section, mj-wrapper').select { |node| node['css-class'].to_s.split.include?('footer-locked') }
  end

  def initialize(mjml:, html: nil, compile_errors: [], public_root: Rails.public_path, # rubocop:disable Metrics/ParameterLists
                 placeholders: EmailCampaigns::TemplateValidator::DEFAULT_KEYS, remote_images: false, fonts: [FONT])
    @mjml = mjml.to_s
    @fonts = fonts
    # nil when the MJML is not compiled (import and AI jobs: no compiler in the production image).
    @html = html&.to_s
    @compile_errors = compile_errors
    @public_root = Pathname.new(public_root).expand_path
    @placeholders = placeholders
    @remote_images = remote_images
    @doc = Nokogiri::HTML5.fragment(@mjml)
  end

  def violations
    @violations = []
    @compile_errors.each { |error| add(:mjml_strict, error) }
    check_tags
    check_unsubscribe
    check_text
    check_buttons
    check_images
    check_placeholders
    add(:html_size, "#{html_bytes} bytes#{' (estimated)' if @html.nil?}") if html_bytes > MAX_HTML_BYTES
    @violations
  end

  def html_bytes
    @html_bytes ||= @html.nil? ? EstimatedSize.bytes(@mjml) : @html.bytesize
  end

  private

  def add(check, detail)
    @violations << Violation.new(check, detail)
  end

  def check_tags
    @doc.css('*').map(&:name).uniq.each do |name|
      allowed = name.start_with?('mj') ? EDITABLE_TAGS : INLINE_TAGS
      add(:editable_tags, name) unless allowed.include?(name)
    end
    self_closed_tags.each { |name| add(:explicit_close_tags, name) }
  end

  # `<mj-x />` means "closed" to MJML but "open" to the editor's HTML parser, which then swallows siblings.
  def self_closed_tags
    names = []
    position = 0
    while (close = @mjml.index('/>', position))
      start = @mjml.rindex('<', close)
      name = start ? tag_name(@mjml[(start + 1)...close]) : ''
      names << name if name.start_with?('mj')
      position = close + 2
    end
    names
  end

  def tag_name(fragment)
    fragment.each_char.take_while { |char| !char.strip.empty? && char != '/' }.join
  end

  def check_unsubscribe
    footers = self.class.footer_sections(@doc)
    links = unsubscribe_links(@doc)
    in_footer = footers.sum { |footer| unsubscribe_links(footer).size }
    placeholder_uses = placeholder_keys(@mjml).count(UNSUBSCRIBE)
    unless footers.size == 1 && links.size == 1 && in_footer == 1 && placeholder_uses == 1
      add(:unsubscribe, "#{footers.size} footer-locked, #{links.size} unsubscribe link(s), #{in_footer} in the footer")
    end
    check_compiled_unsubscribe unless @html.nil?
  end

  def check_compiled_unsubscribe
    html_links = unsubscribe_links(Nokogiri::HTML5(@html)).size
    add(:unsubscribe, "#{html_links} unsubscribe link(s) in the compiled HTML") unless html_links == 1
  end

  def unsubscribe_links(node)
    node.css('a').select { |link| link['href'].to_s.strip == UNSUBSCRIBE_HREF }
  end

  def check_text
    @doc.css('mj-text, mj-button').each do |node|
      check_font_family(node)
      check_font_sizes(node)
    end
    @doc.css('mj-text').each { |node| check_text_contrast(node) }
  end

  def check_font_family(node)
    family = node['font-family'].to_s.split(',').first.to_s.strip.delete('"\'').downcase
    add(:font_family, "#{node.name} #{node['font-family'].inspect}") unless @fonts.include?(family)
  end

  def check_font_sizes(node)
    minimum = in_footer?(node) ? MIN_FOOTER_PX : MIN_BODY_PX
    sizes = [font_px(node)] + node.css('*').filter_map { |inner| style(inner)['font-size'] }.map { |value| px(value) }
    sizes.each { |size| add(:font_size, "#{label(node)} #{size}px < #{minimum}px") if size < minimum }
  end

  def check_text_contrast(node)
    background = background_of(node)
    size = font_px(node)
    needed = size >= LARGE_TEXT_PX && BOLD.include?(node['font-weight'].to_s) ? MIN_LARGE_CONTRAST : MIN_CONTRAST
    colors = [node['color'] || DEFAULT_TEXT_COLOR] + node.css('*').filter_map { |inner| style(inner)['color'] }
    colors.each { |color| check_contrast(color, background, needed, label(node)) }
  end

  def check_buttons
    @doc.css('mj-button').each do |button|
      check_contrast(button['color'] || DEFAULT_BUTTON_COLOR, button['background-color'] || DEFAULT_BUTTON_BACKGROUND,
                     MIN_CONTRAST, "button #{label(button)}")
      height = button_height(button)
      add(:button_height, "#{label(button)} #{height.round(1)}px < #{MIN_BUTTON_PX}px") if height < MIN_BUTTON_PX
    end
  end

  def check_contrast(color, background, needed, where)
    ratio = Contrast.ratio(color, background)
    return add(:contrast, "#{where}: unmeasurable color #{color}/#{background}") if ratio.nil?

    add(:contrast, "#{where}: #{color} on #{background} = #{ratio.round(2)}:1 < #{needed}") if ratio < needed
  end

  # Vertical inner padding plus one line of text: the rendered height of a one-line button.
  def button_height(button)
    padding = (button['inner-padding'] || DEFAULT_INNER_PADDING).split.map { |value| px(value) }
    top = padding.first
    bottom = padding.size >= 3 ? padding[2] : top
    top + bottom + line_px(button['line-height'] || DEFAULT_BUTTON_LINE_HEIGHT, font_px(button))
  end

  def check_images
    @doc.css('mj-image').each do |image|
      src = image['src'].to_s
      add(:image_alt, src) if image['alt'].to_s.strip.empty?
      problem = (@remote_images ? RemoteImage : LocalImage).problem(src, @public_root)
      add(:local_images, "#{src}: #{problem}") if problem
    end
  end

  def check_placeholders
    (placeholder_keys(@mjml).uniq - @placeholders).each { |key| add(:placeholders, key) }
  end

  def placeholder_keys(source)
    source.split('{{').drop(1).map { |chunk| chunk.split('}}', 2).first.strip.delete_prefix('-').strip }
  end

  def background_of(node)
    Background.of(node)
  end

  def in_footer?(node)
    node.ancestors.any? { |parent| parent['css-class'].to_s.split.include?('footer-locked') }
  end

  def font_px(node)
    node['font-size'] ? px(node['font-size']) : DEFAULT_FONT_PX
  end

  def label(node)
    node.text.strip[0, 30].inspect
  end
end
