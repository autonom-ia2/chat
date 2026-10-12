require 'rails_helper'

RSpec.describe CampaignImports::XlsxReader do
  include CampaignImportHelpers

  let(:styles) do
    '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">' \
      '<numFmts count="1"><numFmt numFmtId="164" formatCode="dd/mm/yyyy"/></numFmts>' \
      '<cellXfs count="4"><xf numFmtId="0"/><xf numFmtId="164"/><xf numFmtId="4"/><xf numFmtId="22"/></cellXfs></styleSheet>'
  end

  def workbook(date1904: false)
    properties = date1904 ? '<workbookPr date1904="1"/>' : ''
    '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" ' \
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">' \
      "#{properties}<sheets><sheet name=\"Base\" sheetId=\"1\" r:id=\"rId1\"/></sheets></workbook>"
  end

  def sheet(cells)
    row = cells.map.with_index { |(value, style), index| %(<c r="#{('A'.ord + index).chr}1"#{style && %( s="#{style}")}><v>#{value}</v></c>) }
    %(<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData><row r="1">#{row.join}</row></sheetData></worksheet>)
  end

  def xlsx(cells, with_styles: true, date1904: false, styles_xml: styles)
    files = {
      'xl/workbook.xml' => workbook(date1904: date1904),
      'xl/_rels/workbook.xml.rels' => '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' \
                                      '<Relationship Id="rId1" Target="worksheets/sheet1.xml"/></Relationships>',
      'xl/worksheets/sheet1.xml' => sheet(cells)
    }
    files['xl/styles.xml'] = styles_xml if with_styles
    build_zip(files)
  end

  it 'reads a date-styled number as an ISO date and keeps every other number' do
    values = described_class.new(xlsx([['46309', 1], ['1234.5', 2], ['46309.5', 3], ['46309', nil]])).rows.first.values

    expect(values).to eq(['2026-10-14', '1234.5', '2026-10-14 12:00', '46309'])
  end

  it 'counts from 1904 when the workbook says so' do
    expect(described_class.new(xlsx([['44847', 1]], date1904: true)).rows.first.values).to eq(['2026-10-14'])
  end

  it 'keeps the serial of a file without styles' do
    expect(described_class.new(xlsx([['46309', 1]], with_styles: false)).rows.first.values).to eq(['46309'])
  end

  it 'still reads a file whose styles part is broken, numbers as written' do
    broken = xlsx([['46309', 1], ['Ana', nil]], styles_xml: '<styleSheet><cellXfs><xf numFmtId="14"></cellXfs>')

    expect(described_class.new(broken).rows.first.values).to eq(%w[46309 Ana])
  end

  it 'still reads a file whose styles part the zip reader refuses, numbers as written' do
    reader = described_class.new(xlsx([['46309', 1]]))
    zip = reader.instance_variable_get(:@zip)
    allow(zip).to receive(:read).and_wrap_original do |original, name|
      raise ArgumentError, 'encrypted_xlsx_entry' if name == 'xl/styles.xml'

      original.call(name)
    end

    expect(reader.rows.first.values).to eq(['46309'])
  end
end
