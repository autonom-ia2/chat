# Canonical MJML (#1074): explicit close tags and head defaults resolved into the body.
#
# The e-mail editor (GrapesJS + grapesjs-mjml) reads MJML with the browser HTML parser, where a
# self-closed `<mj-text />` or `<mj-image />` is an OPEN tag that swallows its siblings: defaults in
# <mj-attributes> get nested (the MJML compiler then ignores them) and nested <mj-image>/<mj-divider>
# show up as ghost blocks. Storing canonical MJML closes that door on the server side; the editor
# applies the same rules in mjmlCanonical.js, and both produce the same output for the same input.
#
# The MJML is parsed as XML (where `/>` means what MJML means). The inner HTML of ending tags and
# comments are cut out before parsing and put back verbatim (MjmlEndingContent). The <mj-attributes>
# defaults are then written on each body element and <mj-attributes> is dropped (MjmlHeadDefaults);
# corrupted heads saved by the old editor are read flat, so their defaults come back too. Malformed
# MJML is returned unchanged (and logged) — never mangled.
class EmailCampaigns::MjmlCanonicalizer
  XML_ENTITIES = %w[amp lt gt quot apos].freeze
  MAX_ENTITY_LENGTH = 40
  HEX_DIGITS = '0123456789abcdef'.freeze
  ROOT = 'mj-canonical-root'.freeze

  def self.call(mjml)
    new(mjml).call
  end

  def initialize(mjml)
    @mjml = mjml.to_s
  end

  def call
    return @mjml if @mjml.empty?

    cut = EmailCampaigns::MjmlEndingContent.new(@mjml)
    root = parse(normalize_entities(cut.skeleton))
    return malformed if root.nil?

    ctx = root_context(root)
    cut.restore(root.children.map { |node| serialize(node, ctx) }.join)
  end

  private

  def malformed
    Rails.logger.warn('[EmailCampaigns::MjmlCanonicalizer] MJML is not well-formed; kept unchanged')
    @mjml
  end

  # Wrapped in a synthetic root so fragments (several sibling sections) parse too.
  def parse(skeleton)
    Nokogiri::XML("<#{ROOT}>#{skeleton}</#{ROOT}>") { |config| config.strict.nonet }.root
  rescue Nokogiri::XML::SyntaxError
    nil
  end

  # ---- entities: XML knows only five; HTML names become numeric, a bare & becomes &amp; ----

  def normalize_entities(src)
    out = +''
    pos = 0
    while (amp = src.index('&', pos))
      out << src[pos...amp]
      semi = src.index(';', amp)
      name = semi && semi - amp <= MAX_ENTITY_LENGTH ? src[(amp + 1)...semi] : nil
      entity = entity_for(name)
      out << (entity || '&amp;')
      pos = entity ? semi + 1 : amp + 1
    end
    out << src[pos..]
  end

  def entity_for(name)
    return nil if name.blank?
    return "&#{name};" if XML_ENTITIES.include?(name) || char_reference?(name)

    numeric_html_entity(name)
  end

  # `&copy;` -> `&#169;`; nil when the name is not an HTML entity.
  def numeric_html_entity(name)
    return nil unless name.each_char.all? { |char| ascii_alnum?(char) }

    text = Nokogiri::HTML5.fragment("&#{name};").text
    return nil if text == "&#{name};"

    text.each_char.map { |char| "&##{char.ord};" }.join
  end

  def char_reference?(name)
    return false unless name.start_with?('#') && name.length > 1

    hex = name[1].casecmp?('x')
    digits = name[(hex ? 2 : 1)..]
    digits.present? && digits.each_char.all? { |char| hex ? HEX_DIGITS.include?(char.downcase) : ascii_digit?(char) }
  end

  def ascii_digit?(char)
    char.between?('0', '9')
  end

  def ascii_alnum?(char)
    ascii_digit?(char) || char.between?('a', 'z') || char.between?('A', 'Z')
  end

  # ---- serialization: explicit close tags, head defaults resolved into the body ----

  Context = Struct.new(:defaults, :in_head, :inherited_classes)

  def root_context(root)
    blocks = root.css('mj-attributes').to_a
    Context.new(blocks.any? ? EmailCampaigns::MjmlHeadDefaults.collect(blocks) : nil, false, nil)
  end

  def serialize(node, ctx)
    return serialize_element(node, ctx) if node.element?
    return "<![CDATA[#{node.content}]]>" if node.cdata?
    return escape_text(node.content) if node.text?
    return "<!--#{node.content}-->" if node.comment?

    ''
  end

  def serialize_element(element, ctx)
    tag = element.name
    # Resolved into the body, and grapesjs-mjml would render its children as blocks.
    return '' if ctx.defaults && tag == 'mj-attributes'

    child_ctx = Context.new(ctx.defaults, ctx.in_head || tag == 'mj-head', element['mj-class'] || ctx.inherited_classes)
    inner = element.children.map { |child| serialize(child, child_ctx) }.join
    "#{open_tag(tag, attributes_for(element, ctx))}#{inner}</#{tag}>"
  end

  def attributes_for(element, ctx)
    return plain_attributes(element) if ctx.defaults.nil? || ctx.in_head

    ctx.defaults.resolve(element, ctx.inherited_classes)
  end

  def plain_attributes(element)
    element.attribute_nodes.to_h { |attr| [attr.name, attr.value] }
  end

  def open_tag(tag, attrs)
    "<#{tag}#{attrs.map { |name, value| %( #{name}="#{escape_attribute(value)}") }.join}>"
  end

  def escape_attribute(value)
    value.gsub('&', '&amp;').gsub('"', '&quot;').gsub('<', '&lt;')
  end

  # `>` stays literal so Liquid comparisons ({% if a > b %}) survive.
  def escape_text(value)
    value.gsub('&', '&amp;').gsub('<', '&lt;')
  end
end
