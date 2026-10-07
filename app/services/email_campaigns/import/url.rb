# URL helpers for the importer (#1099): the scheme as a browser reads it (control characters and spaces inside the
# value are ignored, so `java\tscript:` is `javascript:`), protocol-relative and relative addresses. URI and string
# methods — no regex.
module EmailCampaigns::Import::Url
  SCHEME_CHARS = (('a'..'z').to_a + ('0'..'9').to_a + %w[+ - .]).freeze
  HTTP = %w[http https].freeze
  NBSP = [0x00A0].pack('U').freeze

  module_function

  def compact(value)
    value.to_s.each_char.reject { |char| char.ord <= 32 || char == NBSP }.join
  end

  def scheme(value)
    text = compact(value)
    colon = text.index(':')
    return if colon.nil? || colon.zero?

    candidate = text[0...colon].downcase
    candidate if candidate[0].between?('a', 'z') && candidate.each_char.all? { |char| SCHEME_CHARS.include?(char) }
  end

  def http?(value)
    HTTP.include?(scheme(value))
  end

  def protocol_relative?(value)
    compact(value).start_with?('//')
  end

  def resolve(value, base)
    URI.join(base.to_s, compact(value)).to_s
  rescue URI::Error, ArgumentError
    nil
  end

  # The path of an http(s) address, or the address up to its query when URI cannot read it.
  def path(value)
    text = compact(value)
    URI.parse(text).path.to_s
  rescue URI::InvalidURIError
    text.split('?').first.to_s.split('#').first.to_s
  end
end
