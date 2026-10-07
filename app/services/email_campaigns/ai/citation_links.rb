# The generator uses OpenAI web search, and the model sometimes leaves its source citations as
# markdown inside the copy: `([viagem.hub2you.ai](https://viagem.hub2you.ai/?utm_source=openai))`.
# E-mail clients show that markdown raw. This turns each `[label](http(s)://url)` inside mj-text /
# mj-button content into `<a href="url">label</a>` and drops the `utm_source=openai` tracking the
# search adds. Anything else (other schemes, broken markdown) is left as written. Plain string
# scanning — no regex (#1074).
class EmailCampaigns::Ai::CitationLinks
  TAGS = %w[mj-text mj-button].freeze
  SCHEMES = %w[http:// https://].freeze
  SEARCH_UTM = %w[utm_source openai].freeze
  URL_STOP = [' ', "\t", "\n", "\r", '"', "'", '<', '>'].freeze
  LABEL_STOP = ['[', '<', "\n"].freeze

  def self.call(mjml)
    EmailCampaigns::MjmlEndingContent.map(mjml, TAGS) { |content| new(content).link }
  end

  def initialize(text)
    @text = text
  end

  def link
    return @text unless @text.include?('](')

    out = +''
    pos = 0
    while (open = @text.index('[', pos))
      anchor, finish = anchor_at(open)
      out << @text[pos...open] << (anchor || '[')
      pos = anchor ? finish : open + 1
    end
    out << @text[pos..]
  end

  private

  # [label](url) starting at `open` -> [<a ...>label</a>, index after the closing paren].
  def anchor_at(open)
    close = @text.index(']', open)
    return nil if close.nil? || @text[close + 1] != '('

    label = @text[(open + 1)...close]
    url_end = url_end_at(close + 2)
    url = url_end && valid_label?(label) && clean_url(@text[(close + 2)...url_end])
    return nil unless url

    [%(<a href="#{CGI.escapeHTML(url)}">#{label}</a>), url_end + 1]
  end

  def valid_label?(label)
    label.present? && LABEL_STOP.none? { |stop| label.include?(stop) }
  end

  # Index of the `)` closing the URL; parentheses inside the URL must balance.
  def url_end_at(from)
    depth = 0
    (from...@text.length).each do |i|
      char = @text[i]
      return nil if URL_STOP.include?(char)
      return i if char == ')' && depth.zero?

      depth += 1 if char == '('
      depth -= 1 if char == ')'
    end
    nil
  end

  def clean_url(url)
    return nil unless SCHEMES.any? { |scheme| url.downcase.start_with?(scheme) }

    uri = URI.parse(url)
    uri.query.present? ? without_search_utm(uri, url) : url
  rescue URI::InvalidURIError, ArgumentError
    nil
  end

  def without_search_utm(uri, url)
    params = URI.decode_www_form(uri.query)
    kept = params.reject { |pair| pair == SEARCH_UTM }
    return url if kept.size == params.size

    uri.query = kept.empty? ? nil : URI.encode_www_form(kept)
    uri.to_s
  end
end
