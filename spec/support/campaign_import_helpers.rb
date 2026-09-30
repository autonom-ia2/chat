require 'stringio'
require 'zlib'

module CampaignImportHelpers
  def create_campaign_import(account:, user:, content:, filename: 'base.csv', batch_count: 2, content_type: 'text/csv')
    campaign_import = account.campaign_imports.create!(
      user: user,
      status: :uploaded,
      mode: 'batches',
      campaign_name: 'Campanha Junho',
      batch_count: batch_count,
      source_filename: filename,
      source_content_type: content_type,
      source_byte_size: content.bytesize,
      source_format: File.extname(filename).delete('.').downcase
    )
    campaign_import.original_file.attach(io: StringIO.new(content), filename: filename, content_type: content_type)
    campaign_import
  end

  def create_account_and_user
    account = Account.create!(name: "Conta #{SecureRandom.hex(4)}")
    user = User.create!(
      name: 'Admin User',
      email: "admin-#{SecureRandom.hex(4)}@example.com",
      password: 'Passw0rd!23',
      confirmed_at: Time.current
    )
    AccountUser.create!(account: account, user: user, role: :administrator)
    [account, user]
  end

  def build_xlsx(rows)
    shared_strings = rows.flatten.map(&:to_s)
    shared_string_index = shared_strings.each_with_index.to_h
    sheet_rows = rows.map.with_index(1) do |row, row_index|
      cells = row.map.with_index do |value, column_index|
        reference = "#{('A'.ord + column_index).chr}#{row_index}"
        string_index = shared_string_index[value.to_s]
        %(<c r="#{reference}" t="s"><v>#{string_index}</v></c>)
      end.join
      %(<row r="#{row_index}">#{cells}</row>)
    end.join

    files = {
      '[Content_Types].xml' => %(<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/></Types>),
      '_rels/.rels' => %(<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>),
      'xl/workbook.xml' => %(<?xml version="1.0" encoding="UTF-8"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets></workbook>),
      'xl/_rels/workbook.xml.rels' => %(<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>),
      'xl/sharedStrings.xml' => %(<?xml version="1.0" encoding="UTF-8"?><sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="#{shared_strings.size}" uniqueCount="#{shared_strings.size}">#{shared_strings.map { |value| "<si><t>#{ERB::Util.html_escape(value)}</t></si>" }.join}</sst>),
      'xl/worksheets/sheet1.xml' => %(<?xml version="1.0" encoding="UTF-8"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>#{sheet_rows}</sheetData></worksheet>)
    }
    build_zip(files)
  end

  def build_xlsx_sheets(sheets)
    all_values = sheets.values.flatten(1).flatten.map(&:to_s).uniq
    shared_string_index = all_values.each_with_index.to_h
    workbook_sheets, relationships, worksheet_files = xlsx_sheet_parts(sheets, shared_string_index, [])
    files = worksheet_files.merge(xlsx_workbook_files(all_values, workbook_sheets, relationships))
    build_zip(files)
  end

  def build_xlsx_sheets_with_hidden(sheets, hidden:)
    all_values = sheets.values.flatten(1).flatten.map(&:to_s).uniq
    shared_string_index = all_values.each_with_index.to_h
    workbook_sheets, relationships, worksheet_files = xlsx_sheet_parts(sheets, shared_string_index, hidden)
    files = worksheet_files.merge(xlsx_workbook_files(all_values, workbook_sheets, relationships))
    build_zip(files)
  end

  def xlsx_sheet_parts(sheets, shared_string_index, hidden)
    workbook_sheets = []
    relationships = []
    files = {}
    sheets.each_with_index do |(name, rows), sheet_index|
      sheet_number = sheet_index + 1
      state = hidden.include?(name) ? ' state="hidden"' : ''
      workbook_sheets << %(<sheet name="#{ERB::Util.html_escape(name)}" sheetId="#{sheet_number}" r:id="rId#{sheet_number}"#{state}/>)
      relationships << %(<Relationship Id="rId#{sheet_number}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet#{sheet_number}.xml"/>)
      files["xl/worksheets/sheet#{sheet_number}.xml"] = xlsx_worksheet_xml(rows, shared_string_index)
    end
    [workbook_sheets, relationships, files]
  end

  def xlsx_worksheet_xml(rows, shared_string_index)
    sheet_rows = rows.map.with_index(1) do |row, row_index|
      cells = row.map.with_index do |value, column_index|
        reference = "#{('A'.ord + column_index).chr}#{row_index}"
        %(<c r="#{reference}" t="s"><v>#{shared_string_index.fetch(value.to_s)}</v></c>)
      end.join
      %(<row r="#{row_index}">#{cells}</row>)
    end.join
    %(<?xml version="1.0" encoding="UTF-8"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>#{sheet_rows}</sheetData></worksheet>)
  end

  def xlsx_workbook_files(all_values, workbook_sheets, relationships)
    {
      '[Content_Types].xml' => %(<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/></Types>),
      '_rels/.rels' => %(<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>),
      'xl/workbook.xml' => %(<?xml version="1.0" encoding="UTF-8"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>#{workbook_sheets.join}</sheets></workbook>),
      'xl/_rels/workbook.xml.rels' => %(<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">#{relationships.join}</Relationships>),
      'xl/sharedStrings.xml' => %(<?xml version="1.0" encoding="UTF-8"?><sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="#{all_values.size}" uniqueCount="#{all_values.size}">#{all_values.map { |value| "<si><t>#{ERB::Util.html_escape(value)}</t></si>" }.join}</sst>)
    }
  end

  def build_zip(files)
    output = StringIO.new
    central_directory = StringIO.new
    files.each do |name, content|
      content = content.b
      compressed = raw_deflate(content)
      crc = Zlib.crc32(content)
      local_offset = output.pos
      output << [0x04034b50, 20, 0, 8, 0, 0, crc, compressed.bytesize, content.bytesize, name.bytesize, 0].pack('VvvvvvVVVvv')
      output << name
      output << compressed
      central_directory << [0x02014b50, 20, 20, 0, 8, 0, 0, crc, compressed.bytesize, content.bytesize, name.bytesize, 0, 0, 0, 0, 0, local_offset].pack('VvvvvvvVVVvvvvvVV')
      central_directory << name
    end
    central_directory_offset = output.pos
    central_directory_data = central_directory.string
    output << central_directory_data
    output << [0x06054b50, 0, 0, files.size, files.size, central_directory_data.bytesize, central_directory_offset, 0].pack('VvvvvVVv')
    output.string
  end

  def raw_deflate(content)
    deflater = Zlib::Deflate.new(Zlib::DEFAULT_COMPRESSION, -Zlib::MAX_WBITS)
    deflater.deflate(content, Zlib::FINISH)
  ensure
    deflater&.close
  end
end

RSpec.configure do |config|
  config.include CampaignImportHelpers
end
