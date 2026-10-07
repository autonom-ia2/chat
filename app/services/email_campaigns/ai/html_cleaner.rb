# Cleans the HTML of one MJML ending tag (mj-text, mj-button, mj-raw, mj-title, mj-preview...) or comment for the
# AI, editor and gallery path (#1104), on the parsed fragment — the browser's own HTML5 parser, so split or nested
# tags (`<scr<script>ipt>`) never reassemble — with the rules shared with the import (EmailCampaigns::MarkupPolicy):
# active elements and comments that hide them go with their content, a style sheet that can run code goes, inline
# event handlers go, a URL attribute with another scheme becomes `#`, unsafe CSS declarations go and the others stay.
# A tag name no element can have (`scr<script`) is unwrapped, its text kept. Content that is already safe comes
# back byte for byte (entities, <br/> and Liquid untouched); only a fragment that lost something is written back
# from the tree. Nokogiri and string methods — no regex.
class EmailCampaigns::Ai::HtmlCleaner
  NAME_PUNCTUATION = %w[- _ : .].freeze
  TAG_OPEN = '<'.freeze

  def self.call(html)
    new(html).call
  end

  def initialize(html)
    @html = html.to_s
    @changed = false
  end

  def call
    return @html unless @html.include?(TAG_OPEN)

    fragment = parse
    return '' if fragment.nil?

    walk(fragment)
    @changed ? fragment.to_html : @html
  end

  private

  # Nesting deeper than the parser reads raises: content that cannot be checked is not kept.
  def parse
    Nokogiri::HTML5.fragment(@html)
  rescue ArgumentError => e
    Rails.logger.warn("[EmailCampaigns::Ai::HtmlCleaner] content dropped: #{e.class}")
    nil
  end

  def policy
    EmailCampaigns::MarkupPolicy
  end

  def walk(node)
    node.children.to_a.each { |child| visit(child) }
  end

  def visit(node)
    return remove(node) if drop?(node)
    return unless node.element?

    walk(node)
    attributes(node)
    unwrap(node) unless element_name?(node.name)
  end

  # A comment hiding active markup (Outlook reads conditional comments), an active element, a style sheet that can run code.
  def drop?(node)
    return self.class.call(node.content) != node.content if node.comment?
    return false unless node.element?

    policy.unsafe_element?(node.name) || (node.name == 'style' && policy.unsafe_stylesheet?(node.content))
  end

  def attributes(element)
    element.attribute_nodes.each do |attribute|
      name = attribute.name.downcase
      if policy.event_handler?(name)
        remove(attribute)
      elsif policy.url_attribute?(name)
        url(attribute, name)
      elsif name == 'style'
        style(element, attribute)
      end
    end
  end

  def url(attribute, name)
    return if policy.safe_url_attribute?(name, attribute.value)

    attribute.value = '#'
    @changed = true
  end

  def style(element, attribute)
    return unless policy.unsafe_style?(attribute.value)

    kept = EmailCampaigns::Import::StyleMap.parse(attribute.value).reject { |property, value| policy.unsafe_style?("#{property}:#{value}") }
    kept.empty? ? element.remove_attribute(attribute.name) : attribute.value = EmailCampaigns::Import::StyleMap.dump(kept)
    @changed = true
  end

  def element_name?(name)
    name.each_char.all? { |char| char.between?('a', 'z') || char.between?('A', 'Z') || char.between?('0', '9') || NAME_PUNCTUATION.include?(char) }
  end

  def unwrap(element)
    element.children.to_a.each { |child| element.add_previous_sibling(child) }
    remove(element)
  end

  def remove(node)
    node.remove
    @changed = true
  end
end
