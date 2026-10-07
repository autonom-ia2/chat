# Ceilings of a template import (#1099), checked before any heavy work: 500 KB of markup, 5,000 elements, 40 levels of
# nesting, 2,000 stylesheet rules and a time budget of its own for the CSS inliner.
module EmailCampaigns::Import::Limits
  MAX_BYTES = 500 * 1024
  MAX_ELEMENTS = 5_000
  MAX_DEPTH = 40
  MAX_CSS_RULES = 2_000
  CSS_SECONDS = 3.0
  # Hard stop of the HTML parser itself, far above MAX_DEPTH so the friendlier check below runs first.
  PARSER_DEPTH = 400
  BOM = [0xFEFF].pack('U').freeze

  module_function

  # The input as valid UTF-8 text, or an error when it is too big or blank.
  def source!(input)
    text = input.to_s
    raise EmailCampaigns::Import::Error, :too_large if text.bytesize > MAX_BYTES

    text = text.dup.force_encoding(Encoding::UTF_8)
    text = text.scrub('') unless text.valid_encoding?
    text = text.delete_prefix(BOM)
    raise EmailCampaigns::Import::Error, :empty if text.strip.empty?

    text
  end

  def html!(source)
    doc = Nokogiri::HTML5(source, max_tree_depth: PARSER_DEPTH)
    check_tree!(doc.root)
    doc
  rescue ArgumentError
    raise EmailCampaigns::Import::Error, :too_deep
  end

  # Counts elements and measures the deepest one without recursion.
  def check_tree!(root)
    elements = 0
    stack = [[root, 1]]
    until stack.empty?
      node, depth = stack.pop
      elements += 1
      raise EmailCampaigns::Import::Error, :too_many_nodes if elements > MAX_ELEMENTS
      raise EmailCampaigns::Import::Error, :too_deep if depth > MAX_DEPTH

      node.element_children.each { |child| stack << [child, depth + 1] }
    end
  end
end
