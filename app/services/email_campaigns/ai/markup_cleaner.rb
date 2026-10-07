# Cleans the MJML of the AI, the editor and the gallery (#1104) on the parsed tree, never on the text, with the rules
# the import uses (EmailCampaigns::MarkupPolicy). In the MJML tree: active elements go with their content, inline
# event handlers go, a URL attribute (href, src, background-url...) with another scheme becomes `#`, any other value
# that would carry unsafe CSS into the compiled HTML goes (text attributes such as alt are text, not CSS). Ending-tag
# contents and comments go through HtmlCleaner, a style sheet (mj-style) that can run code or leave its <style> is
# emptied. MJML that is not well-formed is repaired by the lenient parser and cleaned too — never kept unchecked.
# The result is canonical MJML (MjmlCanonicalizer).
class EmailCampaigns::Ai::MarkupCleaner
  TEXT_ATTRIBUTES = %w[alt title].freeze
  STYLESHEET_TAG = 'mj-style'.freeze

  def self.call(mjml)
    new(mjml).call
  end

  def initialize(mjml)
    @mjml = mjml.to_s
  end

  def call
    EmailCampaigns::MjmlCanonicalizer.call(@mjml, recover: true) { |root, cut| clean(root, cut) }
  end

  private

  def policy
    EmailCampaigns::MarkupPolicy
  end

  # Called by MjmlCanonicalizer with the parsed skeleton; returns the rewritten ending-tag contents.
  def clean(root, cut)
    walk(root)
    cut.slots.each_with_index.with_object({}) do |(slot, index), changes|
      content = slot_content(slot)
      changes[index] = content unless content == slot.content
    end
  end

  def walk(node)
    node.children.to_a.each do |child|
      next child.remove if child.cdata? && EmailCampaigns::Ai::HtmlCleaner.call(child.content) != child.content
      next unless child.element?
      next child.remove if policy.unsafe_element?(child.name)

      attributes(child)
      walk(child)
    end
  end

  def attributes(element)
    element.attribute_nodes.each do |attribute|
      name = attribute.name.downcase
      next attribute.remove if policy.event_handler?(name)
      next url(attribute, name) if policy.url_attribute?(name)

      attribute.remove if TEXT_ATTRIBUTES.exclude?(name) && policy.unsafe_style?(attribute.value)
    end
  end

  def url(attribute, name)
    attribute.value = '#' unless policy.safe_url_attribute?(name, attribute.value)
  end

  def slot_content(slot)
    return EmailCampaigns::Ai::HtmlCleaner.call(slot.content) unless slot.tag == STYLESHEET_TAG

    policy.unsafe_stylesheet?(slot.content) ? '' : slot.content
  end
end
