# The text of an imported model, whatever encoding it came in (#1099, delivery B). Bytes that read as UTF-8 are UTF-8;
# otherwise the encoding is the one the address answered with (`declared`), else the page's own <meta charset> (or the
# older http-equiv form), else the western encoding browsers use when nothing is declared (Windows-1252, which is also
# what "iso-8859-1" means on the web). Characters that still cannot be read are dropped and `lossy` says so, for the
# report to warn. Nokogiri and string methods — no regex.
module EmailCampaigns::Import::Charset
  FALLBACK = Encoding::Windows_1252
  # Labels the web reads as Windows-1252 (WHATWG Encoding Standard).
  WESTERN = [Encoding::ISO_8859_1, Encoding::US_ASCII].freeze
  UTF16_BOMS = { "\xFF\xFE".b => Encoding::UTF_16LE, "\xFE\xFF".b => Encoding::UTF_16BE }.freeze
  REPLACEMENT = [0xFFFD].pack('U').freeze
  CHARSET_PARAM = 'charset='.freeze

  Text = Data.define(:text, :lossy)

  module_function

  def decode(bytes, declared: nil)
    raw = bytes.to_s.b
    utf8 = raw.dup.force_encoding(Encoding::UTF_8)
    return Text.new(text: utf8, lossy: false) if utf8.valid_encoding?

    encoding = bom(raw) || find(declared) || find(meta(raw)) || FALLBACK
    return Text.new(text: utf8.scrub(''), lossy: true) if encoding == Encoding::UTF_8

    convert(raw, encoding)
  end

  def bom(raw)
    UTF16_BOMS.find { |mark, _encoding| raw.start_with?(mark) }&.last
  end

  def convert(raw, encoding)
    text = raw.dup.force_encoding(encoding).encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: REPLACEMENT)
    Text.new(text: text.delete(REPLACEMENT), lossy: text.include?(REPLACEMENT))
  rescue Encoding::ConverterNotFoundError
    convert(raw, FALLBACK)
  end

  def find(label)
    name = label.to_s.strip.delete('"\'')
    return if name.empty?

    encoding = Encoding.find(name)
    return if encoding.dummy?

    WESTERN.include?(encoding) ? FALLBACK : encoding
  rescue ArgumentError
    nil
  end

  # The charset the page declares, read on a copy where every byte is one character (ASCII markup stays intact).
  def meta(raw)
    doc = EmailCampaigns::Import::Limits.parse do
      Nokogiri::HTML5(raw.dup.force_encoding(Encoding::ISO_8859_1).encode(Encoding::UTF_8),
                      max_tree_depth: EmailCampaigns::Import::Limits::PARSER_DEPTH)
    end
    doc.at_css('meta[charset]')&.[]('charset') || http_equiv(doc)
  end

  def http_equiv(doc)
    doc.css('meta[http-equiv][content]').each do |node|
      next unless node['http-equiv'].strip.casecmp?('content-type')

      found = from_content_type(node['content'])
      return found if found
    end
    nil
  end

  # "text/html; charset=iso-8859-1" → "iso-8859-1".
  def from_content_type(value)
    param = value.to_s.split(';').drop(1).map(&:strip).find { |part| part.downcase.start_with?(CHARSET_PARAM) }
    param && param[CHARSET_PARAM.length..].strip.delete('"\'').presence
  end
end
