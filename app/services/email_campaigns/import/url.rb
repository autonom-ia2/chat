# URL helpers for the importer (#1099): the scheme as a browser reads it (control characters and spaces inside the
# value are ignored, so `java\tscript:` is `javascript:`), protocol-relative and relative addresses. An address is
# cleaned the way a browser does before using it: blanks around it and line breaks or tabs inside it go, and what is
# left outside URI's alphabet (a space, an accented letter of a file name) is percent-encoded one character at a time —
# never deleted, or "minha foto.png" would become another file. URI and string methods — no regex.
module EmailCampaigns::Import::Url
  SCHEME_CHARS = (('a'..'z').to_a + ('0'..'9').to_a + %w[+ - .]).freeze
  HTTP = %w[http https].freeze
  NBSP = [0x00A0].pack('U').freeze
  BREAKS = ["\t", "\n", "\r"].freeze
  # Printable ASCII a URI may carry as it is; anything else is encoded.
  UNSAFE_ASCII = ['"', '<', '>', '\\', '^', '`', '{', '|', '}'].freeze

  module_function

  def compact(value)
    value.to_s.each_char.reject { |char| char.ord <= 32 || char == NBSP }.join
  end

  def clean(value)
    chars = value.to_s.each_char.reject { |char| BREAKS.include?(char) }
    chars = chars.drop_while { |char| blank?(char) }.reverse.drop_while { |char| blank?(char) }.reverse
    chars.map { |char| kept?(char) ? char : URI.encode_uri_component(char) }.join
  end

  def blank?(char)
    char.ord <= 32 || char == NBSP
  end

  def kept?(char)
    char.ord.between?(33, 126) && UNSAFE_ASCII.exclude?(char)
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
    URI.join(base.to_s, clean(value)).to_s
  rescue URI::Error, ArgumentError
    nil
  end

  # The path of an http(s) address, or the address up to its query when URI cannot read it.
  def path(value)
    text = clean(value)
    URI.parse(text).path.to_s
  rescue URI::InvalidURIError
    text.split('?').first.to_s.split('#').first.to_s
  end
end
