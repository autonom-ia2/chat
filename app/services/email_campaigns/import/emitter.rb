# Writes the importer's design as MJML (#1099): explicit close tags, attributes escaped, one block per line. The result
# then goes through LockedFooter.ensure (canonical MJML with our footer) and the quality fixes.
class EmailCampaigns::Import::Emitter
  def self.call(document)
    new(document).call
  end

  def initialize(document)
    @document = document
  end

  def call
    ['<mjml>', head, "  <mj-body#{attributes('width' => "#{@document.width}px", 'background-color' => @document.background)}>",
     *@document.sections.map { |section| section(section) }, '  </mj-body>', '</mjml>'].join("\n")
  end

  private

  def head
    parts = []
    parts << "<mj-title>#{escape_text(@document.title)}</mj-title>" if @document.title.present?
    parts << "<mj-preview>#{escape_text(@document.preview)}</mj-preview>" if @document.preview.present?
    "  <mj-head>#{parts.join}</mj-head>"
  end

  def section(section)
    url = section.background_url
    attrs = { 'background-color' => section.background, 'background-url' => url, 'background-size' => url && 'cover',
              'background-repeat' => url && 'no-repeat', 'padding' => section.padding }
    ["    <mj-section#{attributes(attrs)}>", *section.columns.map { |column| column(column) }, '    </mj-section>'].join("\n")
  end

  def column(column)
    attrs = { 'width' => column.width, 'padding' => column.padding, 'background-color' => column.background }
    ["      <mj-column#{attributes(attrs)}>", *column.blocks.map { |block| block(block) }, '      </mj-column>'].join("\n")
  end

  def block(block)
    "        <#{block.tag}#{attributes(block.attrs)}>#{block.content}</#{block.tag}>"
  end

  def attributes(hash)
    hash.compact.map { |name, value| %( #{name}="#{escape_attribute(value.to_s)}") }.join
  end

  def escape_attribute(value)
    value.gsub('&', '&amp;').gsub('"', '&quot;').gsub('<', '&lt;')
  end

  def escape_text(value)
    value.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;')
  end
end
