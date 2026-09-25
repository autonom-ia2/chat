# Excel da exportação (#682): o mínimo de OOXML que o Excel, o LibreOffice e o Google Planilhas abrem, montado com o
# rubyzip que já está no Gemfile. Texto vai como inlineStr, nunca como fórmula; número vai como número. O texto sai como
# o cliente o escreveria: o que começa como fórmula (Cell.formula_start?) leva o estilo quotePrefix em vez do apóstrofo
# que o CSV precisa, e o telefone +55 aparece limpo.
module Autonomia::Prospecting::Export::XlsxFile
  CONTENT_TYPES = <<~XML.freeze
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
      <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
      <Default Extension="xml" ContentType="application/xml"/>
      <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
      <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
      <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
    </Types>
  XML
  ROOT_RELS = <<~XML.freeze
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
    </Relationships>
  XML
  WORKBOOK = <<~XML.freeze
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
      <sheets><sheet name="Leads" sheetId="1" r:id="rId1"/></sheets>
    </workbook>
  XML
  WORKBOOK_RELS = <<~XML.freeze
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
      <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
    </Relationships>
  XML
  # Três formatos: o comum (0), o negrito do cabeçalho (1) e o texto com quotePrefix (2). cellStyles dá o estilo
  # Normal que os leitores esperam.
  STYLES = <<~XML.freeze
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
      <fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts>
      <fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>
      <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
      <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
      <cellXfs count="3"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" quotePrefix="1"/></cellXfs>
      <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
    </styleSheet>
  XML
  HEADER_STYLE = 1
  QUOTED_STYLE = 2
  # Controles que o XML 1.0 não aceita (tudo abaixo do espaço, menos tab, LF e CR), no formato de String#delete.
  INVALID_XML_CHARS = "\u0000-\u0008\u000B\u000C\u000E-\u001F".freeze

  module_function

  def generate(rows)
    buffer = Zip::OutputStream.write_buffer(StringIO.new) do |zip|
      {
        '[Content_Types].xml' => CONTENT_TYPES, '_rels/.rels' => ROOT_RELS, 'xl/workbook.xml' => WORKBOOK,
        'xl/_rels/workbook.xml.rels' => WORKBOOK_RELS, 'xl/styles.xml' => STYLES, 'xl/worksheets/sheet1.xml' => sheet(rows)
      }.each do |name, content|
        zip.put_next_entry(name)
        zip.write(content)
      end
    end
    buffer.string
  end

  def sheet(rows)
    body = rows.each_with_index.map do |row, index|
      style = index.zero? ? HEADER_STYLE : nil
      cells = row.each_with_index.filter_map { |value, column| cell(value, "#{column_name(column)}#{index + 1}", style) }
      %(<row r="#{index + 1}">#{cells.join}</row>)
    end
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' \
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">' \
      "<sheetData>#{body.join}</sheetData></worksheet>"
  end

  def cell(value, reference, style)
    return if value.nil?

    style ||= QUOTED_STYLE if Autonomia::Prospecting::Export::Cell.formula_start?(value)

    style_attribute = style ? %( s="#{style}") : ''
    return %(<c r="#{reference}"#{style_attribute}><v>#{value}</v></c>) if value.is_a?(Numeric)

    %(<c r="#{reference}"#{style_attribute} t="inlineStr"><is><t xml:space="preserve">#{xml_text(value.to_s)}</t></is></c>)
  end

  # O CR vira entidade: solto no XML, o leitor o troca por LF.
  def xml_text(value)
    value.delete(INVALID_XML_CHARS).encode(xml: :text).gsub("\r", '&#13;')
  end

  # 0 -> A, 25 -> Z, 26 -> AA.
  def column_name(index)
    name = +''
    number = index + 1
    while number.positive?
      number, remainder = (number - 1).divmod(26)
      name.prepend((65 + remainder).chr)
    end
    name
  end
end
