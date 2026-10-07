# One round of quality corrections on a parsed MJML design (#1099), called by MjmlCanonicalizer with the skeleton and
# the cut ending-tag contents; changes attributes in place and returns the rewritten contents by slot index.
class EmailCampaigns::Import::QualityFix::Fixes
  include EmailCampaigns::QualityGate::Css

  GATE = EmailCampaigns::QualityGate
  FONT = 'Arial, Helvetica, sans-serif'.freeze
  MAX_ALT = 120

  def initialize(root, cut, checks)
    @root = root
    @cut = cut
    @checks = checks
    @slot_index = cut.slots.each_index.index_by { |index| cut.token(index) }
    @changes = {}
  end

  # check => [selector, fix]; a button fix covers both its contrast and its height.
  STEPS = [[:font_family, 'mj-text, mj-button', :font_family], [:font_size, 'mj-text, mj-button', :font_size],
           [:contrast, 'mj-text', :text_contrast], [:contrast, 'mj-button', :button_contrast],
           [:button_height, 'mj-button', :button_height], [:image_alt, 'mj-image', :alt]].freeze

  def call
    STEPS.each do |check, selector, fix|
      @root.css(selector).each { |node| send(fix, node) } if @checks.include?(check)
    end
    @changes
  end

  private

  def font_family(node)
    family = node['font-family'].to_s.split(',').first.to_s.strip.delete('"\'').downcase
    node['font-family'] = FONT unless family == GATE::FONT
  end

  def font_size(node)
    minimum = footer?(node) ? GATE::MIN_FOOTER_PX : GATE::MIN_BODY_PX
    node['font-size'] = "#{minimum}px" if (node['font-size'] ? px(node['font-size']) : GATE::DEFAULT_FONT_PX) < minimum
    rewrite(node) do |fragment|
      fragment.css('*').count do |inner|
        size = style(inner)['font-size']
        size && px(size) < minimum && set_style(inner, 'font-size', "#{minimum}px")
      end.positive?
    end
  end

  # Text over a background image keeps its color: the image is what the reader sees, so the fallback color says nothing
  # about contrast. The check stays pending for the person to judge.
  def text_contrast(node)
    return if GATE::Background.image?(node)

    background = GATE::Background.of(node)
    needed = needed(node)
    color = node['color'] || GATE::DEFAULT_TEXT_COLOR
    node['color'] = adjusted(color, background, needed)
    rewrite(node) do |fragment|
      fragment.css('*').count do |inner|
        inner_color = style(inner)['color']
        fixed = inner_color && adjusted(inner_color, background, needed)
        fixed && fixed != inner_color && set_style(inner, 'color', fixed)
      end.positive?
    end
  end

  def needed(node)
    large = px(node['font-size'] || "#{GATE::DEFAULT_FONT_PX}px") >= GATE::LARGE_TEXT_PX && GATE::BOLD.include?(node['font-weight'].to_s)
    large ? GATE::MIN_LARGE_CONTRAST : GATE::MIN_CONTRAST
  end

  def adjusted(color, background, needed)
    ratio = GATE::Contrast.ratio(color, background)
    return color if ratio && ratio >= needed

    GATE::Contrast.adjust(color, background, needed)
  end

  def button_contrast(node)
    background = node['background-color'] || GATE::DEFAULT_BUTTON_BACKGROUND
    color = node['color'] || GATE::DEFAULT_BUTTON_COLOR
    return if GATE::Contrast.ratio(color, background).to_f >= GATE::MIN_CONTRAST

    best = %w[#ffffff #000000].max_by { |candidate| GATE::Contrast.ratio(candidate, background).to_f }
    node['color'] = best
    return if GATE::Contrast.ratio(best, background).to_f >= GATE::MIN_CONTRAST

    node['background-color'] = GATE::Contrast.adjust(background, best, GATE::MIN_CONTRAST)
  end

  def button_height(node)
    top, right, bottom, left = sides(node['inner-padding'] || GATE::DEFAULT_INNER_PADDING)
    font = node['font-size'] ? px(node['font-size']) : GATE::DEFAULT_FONT_PX
    missing = GATE::MIN_BUTTON_PX - (top + bottom + line_px(node['line-height'] || GATE::DEFAULT_BUTTON_LINE_HEIGHT, font))
    return if missing <= 0

    extra = (missing / 2.0).ceil
    node['inner-padding'] = [top + extra, right, bottom + extra, left].map { |value| "#{value.round}px" }.join(' ')
  end

  # A CSS padding shorthand as [top, right, bottom, left] in px.
  def sides(value)
    top, right, bottom, left = value.split.map { |part| px(part) }
    right ||= top
    [top, right, bottom || top, left || right]
  end

  def alt(node)
    return if node['alt'].to_s.strip.present?

    node['alt'] = (neighbor_text(node) || file_name(node['src'])).to_s[0, MAX_ALT]
  end

  def neighbor_text(node)
    [node.previous_element, node.next_element].each do |sibling|
      next unless sibling&.name == 'mj-text'

      text = Nokogiri::HTML5.fragment(content(sibling).to_s).text.split.join(' ')
      return text if text.present?
    end
    nil
  end

  def file_name(src)
    base = readable(File.basename(EmailCampaigns::Import::Url.path(src.to_s)).to_s)
    name = base.include?('.') ? base[0...base.rindex('.')] : base
    name.tr('-_', '  ').split.join(' ').presence || 'Imagem'
  end

  # A file name as the person wrote it ("minha%20foto" back to "minha foto").
  def readable(name)
    URI.decode_uri_component(name).force_encoding(Encoding::UTF_8).scrub('')
  rescue ArgumentError
    name
  end

  def footer?(node)
    node.ancestors.any? { |parent| parent['css-class'].to_s.split.include?('footer-locked') }
  end

  def content(node)
    index = @slot_index[node.text]
    index && @changes.fetch(index, @cut.slots[index].content)
  end

  def rewrite(node)
    index = @slot_index[node.text]
    return if index.nil?

    fragment = Nokogiri::HTML5.fragment(@changes.fetch(index, @cut.slots[index].content))
    @changes[index] = fragment.to_html if yield(fragment)
  end

  def set_style(node, property, value)
    declarations = EmailCampaigns::Import::StyleMap.parse(node['style'])
    declarations[property] = value
    node['style'] = EmailCampaigns::Import::StyleMap.dump(declarations)
    true
  end
end
