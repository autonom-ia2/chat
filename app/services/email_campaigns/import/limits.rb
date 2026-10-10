# Ceilings of a template import (#1099), checked before and during the heavy work: 500 KB of markup, 5,000 elements and
# 40 levels of nesting (counted by Budget across every parse of one import), 2,000 stylesheet rules with a time budget of
# their own for the CSS inliner, and one deadline for the whole conversion.
module EmailCampaigns::Import::Limits
  MAX_BYTES = 500 * 1024
  MAX_ELEMENTS = 5_000
  MAX_DEPTH = 40
  MAX_CSS_RULES = 2_000
  CSS_SECONDS = 3.0
  TOTAL_SECONDS = 10.0
  # Hard stop of the HTML parser itself, far above MAX_DEPTH so the friendlier check of Budget runs first.
  PARSER_DEPTH = 400
  # What Nokogiri's ArgumentError says when PARSER_DEPTH is crossed ("Document tree depth limit exceeded").
  PARSER_DEPTH_ERROR = 'depth limit exceeded'.freeze
  BOM = [0xFEFF].pack('U').freeze

  module_function

  # The input as UTF-8 text (Charset::Text, whose `lossy` tells that characters could not be read), or an error when it
  # is too big or blank. `charset` is the encoding the address answered with, when there is one.
  def source!(input, charset: nil)
    bytes = input.to_s.b
    raise EmailCampaigns::Import::Error, :too_large if bytes.bytesize > MAX_BYTES

    decoded = EmailCampaigns::Import::Charset.decode(bytes, declared: charset)
    text = decoded.text.delete_prefix(BOM)
    raise EmailCampaigns::Import::Error, :empty if text.strip.empty?

    decoded.with(text: text)
  end

  # A whole page, parsed within the parser depth and counted against the import's budget.
  def html!(source, budget = EmailCampaigns::Import::Budget.new)
    doc = parse { Nokogiri::HTML5(source, max_tree_depth: PARSER_DEPTH) }
    budget.count!(doc.root)
    doc
  end

  # An HTML fragment parsed within the parser depth (not counted: callers that read client markup count it).
  def fragment(html)
    parse { Nokogiri::HTML5.fragment(html.to_s, max_tree_depth: PARSER_DEPTH) }
  end

  # Runs a parse, turning only the parser's own depth stop into :too_deep; any other error goes up as it is.
  def parse
    yield
  rescue ArgumentError => e
    raise unless e.message.include?(PARSER_DEPTH_ERROR)

    raise EmailCampaigns::Import::Error, :too_deep
  end
end
