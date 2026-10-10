# The text of a part that became an image (#1099, delivery C), one entry per paragraph as the original showed it — a
# heading, a subtitle and a line after a <br> stay apart — with the size, weight, alignment, font and color each one had.
# "Keep only the text" (Fixer) turns each into its own mj-text (`block`). Read from the cleaned markup the report kept for the
# part; without it (an older import), the flat text the report kept is one paragraph. Nokogiri only — no regex.
module EmailCampaigns::Import::PartParagraphs
  Paragraph = Data.define(:text, :size, :bold, :align, :font, :color)
  BLOCKS = %w[p div li h1 h2 h3 h4 h5 h6 td th blockquote center caption].freeze
  MIN_SIZE = EmailCampaigns::QualityGate::MIN_BODY_PX
  MAX_SIZE = 40
  MAX_PARAGRAPHS = 40
  LINE_HEIGHT = '1.4'.freeze
  PADDING = '6px 25px'.freeze

  module_function

  def call(html, fallback)
    root = EmailCampaigns::Import::Limits.fragment(html.to_s)
    found = leaves(root).flat_map { |leaf| lines(leaf) }.first(MAX_PARAGRAPHS)
    return found if found.any?

    text = fallback.to_s.split.join(' ')
    text.empty? ? [] : [paragraph(text, EmailCampaigns::Import::TextStyle.default)]
  end

  # Blocks with text and no other block inside: where one paragraph of the original starts and ends.
  def leaves(root)
    root.css(BLOCKS.join(', ')).select { |node| node.css(BLOCKS.join(', ')).empty? && visible(node.text).present? }
  end

  def lines(leaf)
    style = EmailCampaigns::Import::TextStyle.inherited_for(leaf).inherit(leaf)
    pieces = [+'']
    leaf.traverse do |node|
      pieces << +'' if node.element? && node.name == 'br'
      pieces.last << node.content if node.text?
    end
    pieces.map { |piece| visible(piece) }.reject(&:empty?).map { |text| paragraph(text, style) }
  end

  def paragraph(text, style)
    Paragraph.new(text: text, size: style.font_size.to_f.round.clamp(MIN_SIZE, MAX_SIZE), bold: style.bold, align: style.align || 'left',
                  font: EmailCampaigns::Import::WebFonts.stack(style.font_family), color: style.color)
  end

  # One paragraph as an mj-text; the text goes in as a text node, never as markup.
  def block(document, paragraph)
    attributes = { 'font-family' => paragraph.font, 'font-size' => "#{paragraph.size}px", 'font-weight' => ('700' if paragraph.bold),
                   'align' => paragraph.align, 'color' => paragraph.color, 'line-height' => LINE_HEIGHT, 'padding' => PADDING }.compact
    node = document.create_element('mj-text', attributes)
    node.add_child(document.create_text_node(paragraph.text))
    node
  end

  def visible(text)
    EmailCampaigns::Import::Visibility.visible_text(text.to_s).split.join(' ')
  end
end
