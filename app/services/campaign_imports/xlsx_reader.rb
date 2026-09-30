require 'rexml/document'
require 'zlib'

module CampaignImports
  class XlsxReader
    DEFAULT_MAX_UNCOMPRESSED_BYTES = 50 * 1024 * 1024
    ParsedRow = Struct.new(:number, :values, keyword_init: true)
    ParsedSheet = Struct.new(:name, :rows, keyword_init: true)

    class ZipReader
      Entry = Struct.new(
        :name,
        :compression_method,
        :compressed_size,
        :uncompressed_size,
        :local_header_offset,
        :encrypted,
        keyword_init: true
      )

      CENTRAL_DIRECTORY_SIGNATURE = "PK\x01\x02".b
      END_OF_CENTRAL_DIRECTORY_SIGNATURE = "PK\x05\x06".b
      LOCAL_FILE_HEADER_SIGNATURE = "PK\x03\x04".b

      def initialize(data, max_uncompressed_bytes:)
        @data = data.b
        @max_uncompressed_bytes = max_uncompressed_bytes
        @read_uncompressed_bytes = 0
        @entries = parse_entries
      end

      def read(name)
        entry = @entries[name]
        return nil if entry.nil?
        raise ArgumentError, 'encrypted_xlsx_entry' if entry.encrypted
        raise ArgumentError, 'xlsx_entry_too_large' if entry.uncompressed_size > @max_uncompressed_bytes

        local_header = @data.byteslice(entry.local_header_offset, 30)
        raise ArgumentError, 'invalid_xlsx_zip' unless local_header&.start_with?(LOCAL_FILE_HEADER_SIGNATURE)

        name_length = little_endian_16(local_header, 26)
        extra_length = little_endian_16(local_header, 28)
        data_offset = entry.local_header_offset + 30 + name_length + extra_length
        compressed = @data.byteslice(data_offset, entry.compressed_size)

        case entry.compression_method
        when 0
          track_uncompressed_size!(compressed.bytesize)
          compressed
        when 8
          inflate_limited(compressed)
        else
          raise ArgumentError, 'unsupported_xlsx_compression'
        end
      end

      private

      def parse_entries
        eocd_offset = @data.rindex(END_OF_CENTRAL_DIRECTORY_SIGNATURE)
        raise ArgumentError, 'invalid_xlsx_zip' if eocd_offset.nil?

        entry_count = little_endian_16(@data, eocd_offset + 10)
        central_directory_offset = little_endian_32(@data, eocd_offset + 16)
        entries = {}
        offset = central_directory_offset

        entry_count.times do
          raise ArgumentError, 'invalid_xlsx_zip' unless @data.byteslice(offset, 4) == CENTRAL_DIRECTORY_SIGNATURE

          flags = little_endian_16(@data, offset + 8)
          compression_method = little_endian_16(@data, offset + 10)
          compressed_size = little_endian_32(@data, offset + 20)
          uncompressed_size = little_endian_32(@data, offset + 24)
          file_name_length = little_endian_16(@data, offset + 28)
          extra_length = little_endian_16(@data, offset + 30)
          comment_length = little_endian_16(@data, offset + 32)
          local_header_offset = little_endian_32(@data, offset + 42)
          name = @data.byteslice(offset + 46, file_name_length).force_encoding(Encoding::UTF_8)

          entries[name] = Entry.new(
            name: name,
            compression_method: compression_method,
            compressed_size: compressed_size,
            uncompressed_size: uncompressed_size,
            local_header_offset: local_header_offset,
            encrypted: (flags & 0x0001).positive?
          )
          offset += 46 + file_name_length + extra_length + comment_length
        end

        entries
      end

      def little_endian_16(data, offset)
        data.byteslice(offset, 2).unpack1('v')
      end

      def little_endian_32(data, offset)
        data.byteslice(offset, 4).unpack1('V')
      end

      def inflate_limited(compressed)
        inflater = Zlib::Inflate.new(-Zlib::MAX_WBITS)
        output = +''
        offset = 0

        while offset < compressed.bytesize
          chunk = compressed.byteslice(offset, 16 * 1024)
          offset += chunk.bytesize
          output << inflater.inflate(chunk)
          raise ArgumentError, 'xlsx_file_too_large' if @read_uncompressed_bytes + output.bytesize > @max_uncompressed_bytes
        end

        output << inflater.finish
        track_uncompressed_size!(output.bytesize)
        output
      ensure
        inflater&.close
      end

      def track_uncompressed_size!(bytesize)
        raise ArgumentError, 'xlsx_entry_too_large' if bytesize > @max_uncompressed_bytes

        @read_uncompressed_bytes += bytesize
        raise ArgumentError, 'xlsx_file_too_large' if @read_uncompressed_bytes > @max_uncompressed_bytes
      end
    end

    def initialize(data, max_uncompressed_bytes: default_max_uncompressed_bytes)
      @zip = ZipReader.new(data, max_uncompressed_bytes: max_uncompressed_bytes)
    end

    def rows
      sheets.first&.rows || []
    end

    def sheets
      @sheets ||= workbook_sheets.map do |sheet|
        ParsedSheet.new(name: sheet.fetch(:name), rows: rows_for(sheet.fetch(:path)))
      end
    end

    private

    def workbook_sheets
      workbook = document_for('xl/workbook.xml')
      relationships = workbook_relationships
      sheets_node = find_child(workbook.root, 'sheets')
      result = []
      sheets_node&.each_element do |sheet|
        next unless sheet.name == 'sheet'
        next if %w[hidden veryHidden].include?(sheet.attributes['state'])

        relationship_id = sheet.attributes['r:id']
        target = relationships[relationship_id]
        next if target.to_s.empty?

        result << { name: sheet.attributes['name'].to_s, path: normalize_path('xl', target) }
      end
      raise ArgumentError, 'xlsx_sheet_not_found' if result.empty?

      result
    end

    def rows_for(path)
      sheet = document_for(path)
      sheet_data = find_child(sheet.root, 'sheetData')
      return [] if sheet_data.nil?

      shared_strings = read_shared_strings
      sheet_rows = []
      sheet_data.each_element { |element| sheet_rows << element if element.name == 'row' }
      sheet_rows.map { |row| parse_row(row, shared_strings) }
    end

    def workbook_relationships
      document = document_for('xl/_rels/workbook.xml.rels')
      relationships = {}
      document.root.each_element do |relationship|
        next unless relationship.name == 'Relationship'

        relationships[relationship.attributes['Id']] = relationship.attributes['Target']
      end
      relationships
    end

    def read_shared_strings
      return @shared_strings if defined?(@shared_strings)

      xml = @zip.read('xl/sharedStrings.xml')
      return @shared_strings = [] if xml.to_s.empty?

      document = REXML::Document.new(xml)
      @shared_strings = []
      document.root.each_element do |element|
        @shared_strings << text_content(element) if element.name == 'si'
      end
      @shared_strings
    end

    def parse_row(row, shared_strings)
      values = []
      row.each_element do |cell|
        next unless cell.name == 'c'

        index = column_index(cell.attributes['r'])
        values[index] = cell_value(cell, shared_strings)
      end

      ParsedRow.new(number: row.attributes['r'].to_i, values: values.map { |value| value.to_s })
    end

    def cell_value(cell, shared_strings)
      formula = find_child(cell, 'f')
      return "=#{formula.text}" if formula&.text.to_s != ''

      case cell.attributes['t']
      when 's'
        shared_strings[value_node(cell).to_s.to_i].to_s
      when 'inlineStr'
        text_content(cell)
      else
        value_node(cell).to_s
      end
    end

    def value_node(cell)
      find_child(cell, 'v')&.text
    end

    def document_for(path)
      xml = @zip.read(path)
      raise ArgumentError, 'invalid_xlsx_file' if xml.to_s.empty?

      REXML::Document.new(xml)
    end

    def find_child(element, name)
      return nil if element.nil?

      found = nil
      element.each_element do |child|
        found ||= child if child.name == name
      end
      found
    end

    def text_content(element)
      text_nodes = []
      element.each_recursive do |child|
        text_nodes << child.text if child.respond_to?(:name) && child.name == 't'
      end
      text_nodes.join
    end

    def normalize_path(base, target)
      return target.delete_prefix('/') if target.start_with?('/')

      parts = base.split('/') + target.split('/')
      normalized = []
      parts.each do |part|
        next if part.to_s.empty? || part == '.'

        part == '..' ? normalized.pop : normalized << part
      end
      normalized.join('/')
    end

    def column_index(reference)
      letters = reference.to_s[/\A[A-Z]+/i].to_s.upcase
      letters.chars.reduce(0) { |sum, char| (sum * 26) + char.ord - 64 } - 1
    end

    def default_max_uncompressed_bytes
      return CampaignImports::Config.max_xlsx_uncompressed_size_bytes if defined?(CampaignImports::Config)

      DEFAULT_MAX_UNCOMPRESSED_BYTES
    end
  end
end
