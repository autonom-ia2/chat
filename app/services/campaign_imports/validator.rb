require 'stringio'

module CampaignImports
  class Validator
    NORMALIZED_HEADERS = %w[row_number name phone_number phone_hash batch_index].freeze
    ERROR_HEADERS = %w[row_number name phone_number errors].freeze

    def initialize(campaign_import)
      @campaign_import = campaign_import
    end

    def perform
      campaign_import.update!(status: :validating)
      parsed_file = Parser.new(campaign_import.original_file, filename: campaign_import.source_filename).perform
      validate_parsed_file(parsed_file)
    rescue StandardError => e
      log_unexpected_failure(e)
      mark_validation_failed(['file_could_not_be_processed'], [], exception: e)
    end

    private

    attr_reader :campaign_import

    # Rows with problems no longer block the file: they stay listed (with reasons and in
    # the error CSV) and only the valid rows move on. The file is refused only when a
    # global problem exists or no row at all is valid.
    def validate_parsed_file(parsed_file)
      unsupported_format = !CampaignImports::Config.supported_formats.include?(parsed_file.format)
      return mark_validation_failed(['unsupported_file_format'], []) if unsupported_format

      header_result = HeaderMapper.new(parsed_file.headers).perform
      data_rows = parsed_file.rows.reject { |row| row.values.all? { |value| value.to_s.strip.empty? } }
      global_errors = header_result.errors
      global_errors << 'empty_file' if data_rows.blank?
      global_errors << 'row_limit_exceeded' if row_limit_exceeded?(parsed_file.format, data_rows.size)

      row_results = build_row_results(data_rows, header_result.mapping)
      add_duplicate_errors(row_results)
      valid_count = row_results.count { |row| row[:errors].blank? }
      global_errors << 'no_valid_rows' if data_rows.present? && valid_count.zero? && header_result.errors.empty?
      global_errors << 'batch_count_exceeds_rows' if valid_count.positive? && campaign_import.batch_count.to_i > valid_count
      global_errors << 'too_many_batches' if campaign_import.batch_count.to_i > CampaignImports::Config.max_batches

      return mark_validation_failed(global_errors, row_results) if global_errors.present?

      mark_ready(row_results)
    end

    def log_unexpected_failure(exception)
      Rails.logger.error(
        "[CampaignImports::Validator] import_id=#{campaign_import.id} #{exception.class}: #{SafeLogMessage.call(exception.message)}"
      )
    end

    def build_row_results(rows, mapping)
      rows.map do |row|
        name = value_at(row, mapping[:name])
        phone = value_at(row, mapping[:phone_number])
        errors = formula_errors(row, mapping)
        errors << 'blank_name' if name.blank?

        normalized = normalize_phone(phone, errors)

        {
          row_number: row.row_number,
          raw_name: name,
          raw_phone: phone,
          raw_phone_masked: normalized&.masked || PhoneNormalizer.mask_raw(phone),
          normalized_name: name.squish,
          normalized_phone: normalized&.phone_number,
          normalized_phone_hash: normalized&.hash,
          errors: errors.compact
        }
      end
    end

    def formula_errors(row, mapping)
      row.values.each_with_index.filter_map do |value, index|
        next unless CsvSanitizer.formula_like?(value, allow_phone_plus: index == mapping[:phone_number])

        'formula_detected'
      end.uniq
    end

    def normalize_phone(phone, errors)
      PhoneNormalizer.normalize!(phone)
    rescue PhoneNormalizer::Error => e
      errors << e.message
      nil
    end

    # The first occurrence of a phone stays valid; repeated rows are skipped with a reason.
    def add_duplicate_errors(row_results)
      grouped = row_results.select { |row| row[:normalized_phone_hash].present? && row[:errors].blank? }
                           .group_by { |row| row[:normalized_phone_hash] }
      grouped.each_value do |rows|
        rows.drop(1).each { |row| row[:errors] << 'duplicate_phone_in_file' }
      end
    end

    def mark_ready(row_results)
      valid_rows = row_results.select { |row| row[:errors].blank? }
      invalid_rows = row_results - valid_rows
      ActiveRecord::Base.transaction do
        reset_validation_rows!
        plan = plan_labels(valid_rows)
        valid_rows.each_with_index { |row, index| row[:batch_index] = plan.batch_indexes[index] }
        persist_rows(row_results)
        attach_normalized_csv(valid_rows)
        attach_error_csv([], invalid_rows) if invalid_rows.any?
        attach_report_csv(valid_rows, plan, status: 'ready_to_confirm')
        campaign_import.update!(ready_attributes(row_results, valid_rows, invalid_rows, plan))
      end
    end

    # Old campaign base flow: the base label and one label per batch (LabelPlanner).
    def plan_labels(valid_rows)
      LabelPlanner.new(campaign_import, total_rows: valid_rows.size).perform
    end

    def ready_attributes(row_results, valid_rows, invalid_rows, plan)
      {
        status: :ready_to_confirm,
        total_rows: row_results.size,
        valid_rows: valid_rows.size,
        invalid_rows: invalid_rows.size,
        validated_at: Time.current,
        validation_summary: {
          errors: invalid_rows.flat_map { |row| row[:errors] }.tally,
          warnings: validation_warnings(plan, invalid_rows)
        }
      }
    end

    def mark_validation_failed(global_errors, row_results, exception: nil)
      ActiveRecord::Base.transaction do
        reset_validation_rows!
        persist_rows(row_results)
        attach_error_csv(global_errors, row_results)
        campaign_import.update!(
          status: :validation_failed,
          total_rows: row_results.size,
          valid_rows: row_results.count { |row| row[:errors].blank? },
          invalid_rows: row_results.count { |row| row[:errors].present? },
          validated_at: Time.current,
          validation_summary: validation_summary(global_errors, row_results, exception)
        )
      end
    end

    def reset_validation_rows!
      campaign_import.campaign_import_rows.destroy_all
      campaign_import.campaign_import_labels.destroy_all
      campaign_import.normalized_csv.purge if campaign_import.normalized_csv.attached?
      campaign_import.error_csv.purge if campaign_import.error_csv.attached?
      campaign_import.report_csv.purge if campaign_import.report_csv.attached?
    end

    def persist_rows(row_results)
      row_results.each do |row|
        campaign_import.campaign_import_rows.create!(
          row_number: row[:row_number],
          raw_name: row[:raw_name],
          raw_phone_masked: row[:raw_phone_masked],
          normalized_name: row[:errors].blank? ? row[:normalized_name] : nil,
          normalized_phone_hash: row[:errors].blank? ? row[:normalized_phone_hash] : nil,
          batch_index: row[:batch_index],
          status: row[:errors].blank? ? :valid : :invalid,
          error_messages: row[:errors]
        )
      end
    end

    def attach_normalized_csv(valid_rows)
      rows = valid_rows.map do |row|
        {
          'row_number' => row[:row_number],
          'name' => row[:normalized_name],
          'phone_number' => row[:normalized_phone],
          'phone_hash' => row[:normalized_phone_hash],
          'batch_index' => row[:batch_index]
        }
      end

      campaign_import.normalized_csv.attach(
        io: StringIO.new(CsvSanitizer.generate(NORMALIZED_HEADERS, rows)),
        filename: normalized_filename('normalized'),
        content_type: 'text/csv'
      )
    end

    def attach_error_csv(global_errors, row_results)
      rows = row_results.select { |row| row[:errors].present? }.map do |row|
        {
          'row_number' => row[:row_number],
          'name' => row[:raw_name],
          'phone_number' => row[:raw_phone_masked],
          'errors' => row[:errors].join(';')
        }
      end
      rows << { 'row_number' => '', 'name' => '', 'phone_number' => '', 'errors' => global_errors.join(';') } if global_errors.present?

      campaign_import.error_csv.attach(
        io: StringIO.new(CsvSanitizer.generate(ERROR_HEADERS, rows)),
        filename: normalized_filename('errors'),
        content_type: 'text/csv'
      )
    end

    def attach_report_csv(row_results, plan, status:)
      rows = [
        { 'metric' => 'status', 'value' => status },
        { 'metric' => 'total_rows', 'value' => row_results.size },
        { 'metric' => 'base_label', 'value' => plan.base_label },
        { 'metric' => 'batch_count', 'value' => plan.batch_sizes.size }
      ]

      campaign_import.report_csv.attach(
        io: StringIO.new(CsvSanitizer.generate(%w[metric value], rows)),
        filename: normalized_filename('report'),
        content_type: 'text/csv'
      )
    end

    def validation_summary(global_errors, row_results, exception)
      row_errors = row_results.flat_map { |row| row[:errors] }
      {
        errors: (global_errors + row_errors).compact.tally,
        exception_class: exception&.class&.name
      }.compact
    end

    def validation_warnings(plan, invalid_rows = [])
      warnings = []
      warnings << 'invalid_rows_skipped' if invalid_rows.any?
      warnings << 'large_batch_count' if plan.batch_sizes.size > CampaignImports::Config.warn_batches_above
      warnings
    end

    def value_at(row, index)
      return '' if index.nil?

      row.values[index].to_s.strip
    end

    def row_limit_exceeded?(format, row_count)
      limit = format == 'xlsx' ? CampaignImports::Config.max_xlsx_rows : CampaignImports::Config.max_csv_rows
      row_count > limit
    end

    def normalized_filename(suffix)
      basename = campaign_import.source_filename.to_s.sub(/\.[^.]*\z/, '').presence || "campaign_import_#{campaign_import.id}"
      "#{basename}_#{suffix}.csv"
    end
  end
end
