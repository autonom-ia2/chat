# What e-mail markup may never carry, shared by the import (#1099, EmailCampaigns::Import::Sanitizer) and by the MJML of
# the AI, the editor and the gallery (#1104, EmailCampaigns::Ai::MarkupCleaner): active elements (dropped with their
# content), URL schemes other than http, https, mailto and tel (no scheme is fine: relative addresses, anchors and
# placeholders such as {{ unsubscribe_url }}), inline event handlers and CSS that can run code or reach outside.
# Values are read the way a browser reads them, and then some: entities decoded until nothing changes (so a
# double-encoded scheme is caught too) and control characters or spaces inside the scheme ignored. Nokogiri and
# string methods — no regex.
module EmailCampaigns::MarkupPolicy
  UNSAFE_ELEMENTS = %w[script iframe frame frameset object embed applet svg math form base link canvas audio param noscript
                       template].freeze
  # Inline CSS markers; the import refuses any url() (its background images are read apart), the AI path only those
  # not pointing at http(s).
  UNSAFE_CSS = ['url(', 'expression', 'javascript:', 'vbscript:', 'behavior', '-moz-binding', '@import', '\\', '<'].freeze
  # A whole style sheet (mj-style, <style>): what runs code or leaves the sheet.
  UNSAFE_STYLESHEET = ['expression', 'javascript:', 'vbscript:', '-moz-binding', '<'].freeze
  SAFE_SCHEMES = %w[http https mailto tel].freeze
  URL_ATTRIBUTES = %w[href src srcset background background-url poster action formaction xlink:href lowsrc dynsrc longdesc
                      data codebase cite].freeze
  CSS_URL = 'url('.freeze
  MAX_DECODE = 5

  module_function

  def unsafe_element?(name)
    UNSAFE_ELEMENTS.include?(name.to_s.downcase.split(':').last)
  end

  def event_handler?(name)
    name.to_s.downcase.split(':').last.to_s.start_with?('on')
  end

  def url_attribute?(name)
    URL_ATTRIBUTES.include?(name.to_s.downcase)
  end

  # Every candidate of a srcset, or the single address of any other URL attribute.
  def safe_url_attribute?(name, value)
    return safe_url?(value) unless name.to_s.casecmp?('srcset')

    value.to_s.split(',').all? { |candidate| safe_url?(candidate.split.first.to_s) }
  end

  def safe_url?(value)
    scheme = EmailCampaigns::Import::Url.scheme(decoded(value))
    scheme.nil? || SAFE_SCHEMES.include?(scheme)
  end

  # The import's rule: any marker, url() included.
  def unsafe_css?(value)
    lower = EmailCampaigns::Import::Url.compact(value).downcase
    UNSAFE_CSS.any? { |marker| lower.include?(marker) }
  end

  # The AI/editor rule for one declaration or attribute value: any marker but url(), or a url() that is not http(s).
  def unsafe_style?(value)
    lower = EmailCampaigns::Import::Url.compact(decoded(value)).downcase
    return true if (UNSAFE_CSS - [CSS_URL]).any? { |marker| lower.include?(marker) }

    lower.split(CSS_URL).drop(1).any? { |inside| !EmailCampaigns::Import::Url.http?(inside.split(')').first.to_s.delete(%('"))) }
  end

  def unsafe_stylesheet?(css)
    lower = EmailCampaigns::Import::Url.compact(css).downcase
    UNSAFE_STYLESHEET.any? { |marker| lower.include?(marker) }
  end

  # Character references decoded until the value stops changing. A `<` is read as text, never as a tag.
  def decoded(value)
    text = value.to_s
    MAX_DECODE.times do
      return text unless text.include?('&')

      next_text = Nokogiri::HTML5.fragment(text.gsub('<', '&lt;')).text
      return text if next_text == text

      text = next_text
    end
    text
  end
end
