# Removes what the reader never sees in an imported model (#1099) so it cannot travel into the editable copy as spam or
# a hidden trap: elements hidden by display/visibility/opacity/mso-hide, collapsed to zero height or width, clipped
# away or pushed off screen (position or text-indent), text in a font under 2px (relative sizes included), text with a
# transparent color or the color of its background — unless a background image is behind it, since the image is what
# the reader sees — and tracking pixels (a side of 1px or less). The first hidden text before anything visible is the
# inbox preview: it is kept as the preheader. Every removed text and image, background images included, is recorded.
class EmailCampaigns::Import::Visibility
  Context = Struct.new(:color, :background, :font_size, :clear, :image)
  # Zero-width, joiners, byte-order mark, figure and no-break spaces, soft hyphen: what preheader padding is made of.
  INVISIBLE = [0x200B, 0x200C, 0x200D, 0xFEFF, 0x034F, 0x2007, 0x00A0, 0x00AD, 0x2060].map { |code| [code].pack('U') }.freeze
  MIN_FONT_PX = 2
  BASE_FONT_PX = 16.0
  SAME_COLOR_RATIO = 1.1
  # A position or indent this far to the left or top puts content off screen.
  OFFSCREEN_PX = -500
  POSITIONED = %w[absolute fixed].freeze
  CLEAR_COLORS = %w[transparent].freeze

  def self.call(root, report)
    new(root, report).call
  end

  def self.visible_text(text)
    text.to_s.each_char.map { |char| INVISIBLE.include?(char) ? ' ' : char }.join.split.join(' ')
  end

  def initialize(root, report)
    @root = root
    @report = report
    @seen = false
  end

  def call
    walk(@root, Context.new(nil, nil, nil, false, false))
    @root
  end

  private

  def walk(node, context)
    node.children.to_a.each do |child|
      next text(child, context) if child.text?
      next unless child.element?

      element(child, context)
    end
  end

  def element(child, context)
    style = EmailCampaigns::Import::StyleMap.parse(child['style'])
    return image(child, style) if child.name == 'img'
    return hide(child) if hidden?(style)

    walk(child, inherit(context, child, style))
  end

  def image(child, style)
    return pixel(child) if hidden?(style) || pixel?(child, style)

    @seen = true
  end

  HIDING = { 'display' => 'none', 'visibility' => 'hidden', 'mso-hide' => 'all' }.freeze

  def hidden?(style)
    value = ->(name) { EmailCampaigns::Import::StyleMap.plain(style[name]).downcase }
    return true if HIDING.any? { |name, hiding| value.call(name) == hiding } || transparent?(value.call('opacity'))

    clipped?(value.call('clip')) || offscreen?(style, value.call('position')) || collapsed?(style, value.call('overflow'))
  end

  def collapsed?(style, overflow)
    overflow == 'hidden' && %w[max-height height max-width width].any? { |name| EmailCampaigns::Import::StyleMap.px(style[name])&.zero? }
  end

  # clip: rect(top, right, bottom, left) that leaves no area.
  def clipped?(clip)
    return false unless clip.start_with?('rect(')

    sides = clip.delete_prefix('rect(').delete_suffix(')').tr(',', ' ').split.map { |side| EmailCampaigns::Import::StyleMap.px(side) }
    return false unless sides.size == 4 && sides.all?

    top, right, bottom, left = sides
    bottom <= top || right <= left
  end

  def offscreen?(style, position)
    indent = EmailCampaigns::Import::StyleMap.px(style['text-indent'])
    return true if indent && indent <= OFFSCREEN_PX
    return false unless POSITIONED.include?(position)

    %w[left top].any? { |side| (EmailCampaigns::Import::StyleMap.px(style[side]) || 0) <= OFFSCREEN_PX }
  end

  def transparent?(opacity)
    opacity.start_with?('0', '.') && opacity.to_f.zero?
  end

  def pixel?(image, style)
    sides = [image['width'], image['height'], style['width'], style['height']].filter_map do |value|
      EmailCampaigns::Import::StyleMap.px(value) unless value.to_s.strip.empty?
    end
    sides.any? { |side| side <= 1 }
  end

  def text(node, context)
    return if self.class.visible_text(node.content).empty?
    return @seen = true unless invisible?(context)

    @report.drop_text(node.content, :hidden)
    @report.add(:hidden_text_removed)
    node.remove
  end

  def invisible?(context)
    return true if context.clear || tiny?(context.font_size)
    return false if context.image || context.color.nil? || context.background.nil?

    ratio = EmailCampaigns::QualityGate::Contrast.ratio(context.color, context.background)
    ratio.present? && ratio < SAME_COLOR_RATIO
  end

  def tiny?(font_size)
    font_size.present? && font_size < MIN_FONT_PX
  end

  def hide(element)
    text = self.class.visible_text(element.text)
    if preheader?(text, element)
      @report.preheader = text
      @report.add(:preheader_kept)
    elsif text.present?
      @report.drop_text(text, :hidden)
      @report.add(:hidden_text_removed)
    end
    element.css('a[href]').each { |link| @report.drop_link(link['href'], :hidden) }
    element.css('img').each { |image| pixel(image) }
    [element, *element.css('[data-import-bg]')].each { |node| @report.drop_image(node['data-import-bg'], :hidden) }
    element.remove
  end

  def preheader?(text, element)
    text.present? && !@seen && @report.preheader.nil? && element.css('img').empty?
  end

  def pixel(image)
    @report.add(:tracking_removed)
    @report.drop_image(image['src'], :tracking)
    image.remove
  end

  def inherit(context, element, style)
    color = EmailCampaigns::Import::StyleMap.color(style['color']) || EmailCampaigns::Import::StyleMap.color(element['color'])
    Context.new(color || context.color, background(element, style) || context.background, font_size(style['font-size'], context.font_size),
                color ? false : clear?(style['color']) || context.clear, context.image || element['data-import-bg'].present?)
  end

  def background(element, style)
    EmailCampaigns::Import::StyleMap.color(style['background-color']) || EmailCampaigns::Import::StyleMap.color(element['bgcolor'])
  end

  # Relative sizes (%, em) scale the inherited size; px, pt and rem stand on their own.
  def font_size(value, inherited)
    text = EmailCampaigns::Import::StyleMap.plain(value).downcase
    base = inherited || BASE_FONT_PX
    return base * text.delete_suffix('%').to_f / 100 if text.end_with?('%')
    return base * text.delete_suffix('em').to_f if text.end_with?('em') && !text.end_with?('rem')

    EmailCampaigns::Import::StyleMap.px(text) || inherited
  end

  # transparent, or rgba()/hsla() with an alpha of zero.
  def clear?(value)
    text = EmailCampaigns::Import::StyleMap.plain(value).downcase.delete(' ')
    return true if CLEAR_COLORS.include?(text)
    return false unless text.start_with?('rgba(', 'hsla(')

    parts = text.split('(', 2).last.to_s.delete_suffix(')').split(',')
    parts.size == 4 && parts.last.to_f.zero? && parts.last.start_with?('0', '.')
  end
end
