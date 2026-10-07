# Removes what the reader never sees in an imported model (#1099) so it cannot travel into the editable copy as spam or
# a hidden trap: elements hidden by display/visibility/opacity/mso-hide or collapsed to zero height, text in a font
# under 2px, text the color of its background, and tracking pixels (a side of 1px or less). The first hidden text
# before anything visible is the inbox preview: it is kept as the preheader. Every removed text and image is recorded.
class EmailCampaigns::Import::Visibility
  Context = Struct.new(:color, :background, :font_size)
  # Zero-width, joiners, byte-order mark, figure and no-break spaces, soft hyphen: what preheader padding is made of.
  INVISIBLE = [0x200B, 0x200C, 0x200D, 0xFEFF, 0x034F, 0x2007, 0x00A0, 0x00AD, 0x2060].map { |code| [code].pack('U') }.freeze
  MIN_FONT_PX = 2
  SAME_COLOR_RATIO = 1.1

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
    walk(@root, Context.new(nil, nil, nil))
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

    collapsed = %w[max-height height].any? { |name| EmailCampaigns::Import::StyleMap.px(style[name])&.zero? }
    collapsed && value.call('overflow') == 'hidden'
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
    return true if context.font_size && context.font_size < MIN_FONT_PX
    return false unless context.color && context.background

    ratio = EmailCampaigns::QualityGate::Contrast.ratio(context.color, context.background)
    ratio.present? && ratio < SAME_COLOR_RATIO
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
    Context.new(
      EmailCampaigns::Import::StyleMap.color(style['color']) || EmailCampaigns::Import::StyleMap.color(element['color']) || context.color,
      EmailCampaigns::Import::StyleMap.color(style['background-color']) || EmailCampaigns::Import::StyleMap.color(element['bgcolor']) ||
        context.background,
      EmailCampaigns::Import::StyleMap.px(style['font-size']) || context.font_size
    )
  end
end
