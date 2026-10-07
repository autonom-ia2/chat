# Outlook-only markup of an imported model (#1099). Conditional comments are comments to the parser, so the branch
# "for every client but Outlook" (written outside them) is what stays. The real content sometimes exists only inside
# them: a VML button gets rebuilt as a plain link (unless the same link already exists outside) and a VML background
# image is moved onto its cell. Every comment then leaves — including comments with sensitive data. Nokogiri only.
class EmailCampaigns::Import::Outlook
  CONDITIONAL = '[if'.freeze
  OPEN_END = ']>'.freeze
  CLOSE = '<![endif]'.freeze
  BUTTON = 'v:roundrect'.freeze
  BACKGROUNDS = %w[v:fill v:image].freeze
  BACKGROUND_HOLDERS = %w[td th table div].freeze
  BUTTON_STYLE = 'display:inline-block;padding:12px 24px;text-decoration:none;font-weight:bold'.freeze

  def self.call(root, report)
    new(root, report).call
  end

  def initialize(root, report)
    @root = root
    @report = report
  end

  def call
    comments = @root.xpath('.//comment()')
    conditional = comments.select { |comment| comment.content.lstrip.start_with?(CONDITIONAL) }
    @report.add(:outlook_only) if conditional.any?
    conditional.each { |comment| recover(comment) }
    comments.each(&:remove)
    @root
  end

  private

  def recover(comment)
    markup = inner(comment.content)
    return unless markup.downcase.include?('v:')

    vml = Nokogiri::HTML5.fragment(markup)
    elements = vml.css('*')
    button = elements.find { |element| element.name == BUTTON }
    rebuild_button(comment, button) if button
    background = elements.find { |element| BACKGROUNDS.include?(element.name) && element['src'].present? }
    move_background(comment, background['src']) if background
  end

  def inner(content)
    start = content.index(OPEN_END)
    finish = content.rindex(CLOSE)
    return '' if start.nil?

    content[(start + OPEN_END.length)...(finish || content.length)]
  end

  def rebuild_button(comment, button)
    href = button['href'].to_s.strip
    text = button.text.split.join(' ')
    return if href.empty? || text.empty? || equivalent?(comment.parent, href)

    comment.add_next_sibling(link(comment.document, button, href, text))
    @report.add(:vml_button_recovered)
    @report.recover_text(text)
  end

  def link(document, button, href, text)
    color = EmailCampaigns::Import::StyleMap.parse(button.at_css('center')&.[]('style'))['color']
    style = { 'background-color' => EmailCampaigns::Import::StyleMap.color(button['fillcolor']),
              'color' => EmailCampaigns::Import::StyleMap.color(color) || '#ffffff' }.compact
    node = document.create_element('a', text, 'href' => href)
    node['style'] = "#{EmailCampaigns::Import::StyleMap.dump(style)};#{BUTTON_STYLE}"
    node
  end

  # Same destination (ignoring query and fragment) already linked outside the Outlook branch.
  def equivalent?(parent, href)
    return false if parent.nil?

    target = bare(href)
    parent.css('a[href]').any? { |anchor| bare(anchor['href']) == target }
  end

  def bare(href)
    href.to_s.strip.split('?').first.to_s.split('#').first.to_s.delete_suffix('/')
  end

  def move_background(comment, src)
    holder = comment.ancestors.find { |node| node.element? && BACKGROUND_HOLDERS.include?(node.name) }
    return if holder.nil? || holder['background'].present? || holder['style'].to_s.include?('url(')

    holder['background'] = src
  end
end
