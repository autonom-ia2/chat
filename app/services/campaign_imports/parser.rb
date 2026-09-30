require 'csv'

module CampaignImports
  class Parser
    ParsedFile = Struct.new(:headers, :rows, :format, :tables, keyword_init: true)
    ParsedRow = Struct.new(:row_number, :values, keyword_init: true)
    ParsedTable = Struct.new(:name, :rows, :delimiter, keyword_init: true)

    SUPPORTED_FORMATS = %w[csv xlsx].freeze
    CSV_DELIMITERS = [',', ';', "\t", '|'].freeze

    def initialize(attachment, filename:)
      @attachment = attachment
      @filename = filename.to_s
    end

    def perform
      raise ArgumentError, 'unsupported_file_format' unless SUPPORTED_FORMATS.include?(format)

      format == 'csv' ? parse_csv : parse_xlsx
    end

    private

    def parse_csv
      source = normalized_csv_source
      delimiter = detect_csv_delimiter(source)
      raw_rows = CSV.parse(source, col_sep: delimiter, liberal_parsing: true)
      table_rows = raw_rows.each_with_index.map do |row, index|
        ParsedRow.new(row_number: index + 1, values: Array(row).map(&:to_s))
      end
      headers = normalize_headers(table_rows.first&.values || [])

      ParsedFile.new(
        headers: headers,
        rows: table_rows.drop(1),
        format: format,
        tables: [ParsedTable.new(name: 'CSV', rows: table_rows, delimiter: delimiter)]
      )
    end

    def parse_xlsx
      sheets = CampaignImports::XlsxReader.new(read_source).sheets
      tables = sheets.map do |sheet|
        rows = sheet.rows.map { |row| ParsedRow.new(row_number: row.number, values: row.values) }
        ParsedTable.new(name: sheet.name, rows: rows, delimiter: nil)
      end
      first_rows = tables.first&.rows || []
      headers = normalize_headers(first_rows.first&.values || [])

      ParsedFile.new(headers: headers, rows: first_rows.drop(1), format: format, tables: tables)
    end

    def normalized_csv_source
      source = read_source.to_s.b
      return transcode_utf16(source.byteslice(2..), Encoding::UTF_16LE) if source.start_with?("\xFF\xFE".b)
      return transcode_utf16(source.byteslice(2..), Encoding::UTF_16BE) if source.start_with?("\xFE\xFF".b)

      source = source.byteslice(3..) if source.start_with?("\xEF\xBB\xBF".b)
      utf8 = source.dup.force_encoding(Encoding::UTF_8)
      return utf8 if utf8.valid_encoding?

      source.dup.force_encoding(Encoding::Windows_1252)
            .encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "\uFFFD")
    end

    def transcode_utf16(source, encoding)
      source.dup.force_encoding(encoding).encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "\uFFFD")
    end

    def detect_csv_delimiter(source)
      candidates = CSV_DELIMITERS.filter_map { |delimiter| delimiter_candidate(source, delimiter) }
      candidates.max_by(&:last)&.first || ','
    end

    def delimiter_candidate(source, delimiter)
      widths = sampled_row_widths(source, delimiter)
      return if widths.empty?

      multi_column_widths = widths.select { |width| width > 1 }
      modal_width, modal_count = multi_column_widths.tally.max_by { |width, count| [count, width] } || [1, 0]
      score = [
        multi_column_widths.length,
        modal_count,
        modal_count.positive? ? modal_count.to_f / multi_column_widths.length : 0,
        modal_width,
        -CSV_DELIMITERS.index(delimiter)
      ]
      [delimiter, score]
    rescue CSV::MalformedCSVError, ArgumentError
      nil
    end

    def sampled_row_widths(source, delimiter)
      CSV.new(source, col_sep: delimiter, liberal_parsing: true)
         .first(50)
         .reject { |row| Array(row).all? { |value| value.to_s.strip.empty? } }
         .map(&:length)
    end

    def normalize_headers(headers)
      Array(headers).map.with_index do |header, index|
        value = header.to_s
        value = value.delete_prefix("\uFEFF") if index.zero?
        value
      end
    end

    def read_source
      if @attachment.respond_to?(:open)
        @attachment.open do |file|
          file.binmode
          return file.read
        end
      end

      @attachment.respond_to?(:read) ? @attachment.read : @attachment.to_s
    end

    def format
      @format ||= File.extname(@filename).delete('.').downcase
    end
  end
end
