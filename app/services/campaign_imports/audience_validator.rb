require 'digest'

# Validates a Públicos (#992) spreadsheet. Unlike the WhatsApp base validator it reads name,
# mobile phone, email and company (all optional) through SpreadsheetReader and keeps the other
# columns per row. A row is valid when it has a valid phone OR a valid email; the first
# occurrence of a phone or email wins. When the columns could not be found with confidence the
# import stops at needs_column_choice until the user picks them (PATCH .../columns).
class CampaignImports::AudienceValidator < CampaignImports::Validator
  TARGETS = CampaignImports::SpreadsheetReader::TARGETS
  AUDIENCE_NORMALIZED_HEADERS = %w[row_number name phone_number phone_hash email email_hash company_name batch_index].freeze
  AUDIENCE_ERROR_HEADERS = %w[row_number name phone_number email errors].freeze

  private

  def validate_parsed_file(parsed_file)
    return mark_validation_failed(['unsupported_file_format'], []) unless CampaignImports::Config.supported_formats.include?(parsed_file.format)

    @reading = read(parsed_file)
    return mark_needs_column_choice if @reading.needs_column_choice?

    row_results = build_row_results(@reading.rows, @reading.mapping)
    add_duplicate_errors(row_results)
    global_errors = audience_global_errors(parsed_file.format, row_results)
    return mark_validation_failed(global_errors, row_results) if global_errors.present?

    mark_ready(row_results)
  rescue CampaignImports::SpreadsheetReader::Error => e
    mark_validation_failed([e.message], [])
  end

  def audience_global_errors(format, row_results)
    errors = []
    errors << 'row_limit_exceeded' if row_limit_exceeded?(format, row_results.size)
    errors << 'no_valid_rows' if row_results.none? { |row| row[:errors].blank? }
    errors
  end

  def read(parsed_file)
    manual = previous_resolution['manual_mapping']
    return CampaignImports::SpreadsheetReader.new(parsed_file).perform unless manual

    CampaignImports::SpreadsheetReader.new(
      parsed_file, explicit_mapping: manual, pinned_header: previous_resolution.slice('header_row', 'table_index')
    ).perform
  end

  def previous_resolution
    @previous_resolution ||= campaign_import.schema_resolution.to_h
  end

  def mark_needs_column_choice
    ActiveRecord::Base.transaction do
      reset_validation_rows!
      campaign_import.update!(
        audience_attributes([]).merge(
          status: :needs_column_choice, total_rows: @reading.rows.size, valid_rows: 0, invalid_rows: 0,
          validated_at: Time.current, validation_summary: { errors: {}, warnings: ['column_choice_needed'] }
        )
      )
    end
  end

  def build_row_results(rows, mapping)
    rows.map { |row| audience_row(row, mapping) }
  end

  def audience_row(row, mapping)
    name, phone, email, company = mapping.values_at(*TARGETS).map { |index| value_at(row, index) }
    contact = contact_fields(phone, email)
    errors = audience_formula_errors(row, mapping) + contact.delete(:errors)
    contact.merge(
      row_number: row.row_number, raw_name: name, normalized_name: name.squish,
      company_name: company.squish.presence, extra_values: extra_values(row), errors: errors
    )
  end

  # A row needs a valid phone or a valid email; when it has neither, say why (or that both are missing).
  def contact_fields(phone, email)
    phone_result, phone_error = normalize_with(CampaignImports::PhoneNormalizer, phone)
    email_result, email_error = normalize_with(EmailCampaigns::EmailNormalizer, email)
    reasons = [phone_error, email_error].compact.presence || ['missing_contact']
    phone_fields(phone, phone_result).merge(email_fields(email, email_result), errors: phone_result || email_result ? [] : reasons)
  end

  def phone_fields(raw, result)
    {
      raw_phone_masked: result&.masked || CampaignImports::PhoneNormalizer.mask_raw(raw),
      normalized_phone: result&.phone_number, normalized_phone_hash: result&.hash
    }
  end

  def email_fields(raw, result)
    {
      email: result&.email, email_hash: result && Digest::SHA256.hexdigest(result.email),
      email_masked: raw.present? ? EmailCampaigns::EmailNormalizer.mask(raw.downcase) : nil
    }
  end

  def normalize_with(normalizer, value)
    return [nil, nil] if value.blank?

    [normalizer.normalize!(value), nil]
  rescue CampaignImports::PhoneNormalizer::Error, EmailCampaigns::EmailNormalizer::Error => e
    [nil, e.message]
  end

  # Only the bound columns become contact data; extra columns are kept as written and every
  # generated CSV escapes formula-like cells (CampaignImports::CsvSanitizer.safe_cell).
  def audience_formula_errors(row, mapping)
    mapping.filter_map do |target, index|
      next if index.nil?

      'formula_detected' if CampaignImports::CsvSanitizer.formula_like?(row.values[index], allow_phone_plus: target == 'phone')
    end.uniq
  end

  def extra_values(row)
    @reading.extra_columns.to_h { |column| [column['key'], value_at(row, column['index'])] }.compact_blank
  end

  def add_duplicate_errors(row_results)
    seen = { phone: Set.new, email: Set.new }
    row_results.each do |row|
      next if row[:errors].present?

      if seen[:phone].include?(row[:normalized_phone_hash])
        row[:errors] << 'duplicate_phone_in_file'
      elsif seen[:email].include?(row[:email_hash])
        row[:errors] << 'duplicate_email_in_file'
      else
        seen[:phone] << row[:normalized_phone_hash] if row[:normalized_phone_hash]
        seen[:email] << row[:email_hash] if row[:email_hash]
      end
    end
  end

  def ready_attributes(row_results, valid_rows, invalid_rows, plan)
    super.merge(audience_attributes(valid_rows))
  end

  def mark_validation_failed(global_errors, row_results, exception: nil)
    super
    campaign_import.update!(audience_attributes([])) if @reading
  end

  def audience_attributes(valid_rows)
    resolution = @reading.resolution
    resolution = resolution.merge('manual_mapping' => previous_resolution['manual_mapping']) if previous_resolution['manual_mapping']
    resolution = resolution.merge('jev' => previous_resolution['jev']) if resolution['method'] == 'manual' && previous_resolution['jev']
    {
      channels: channels_for(valid_rows),
      extra_columns: @reading.extra_columns.pluck('key'),
      schema_resolution: resolution
    }
  end

  def channels_for(valid_rows)
    {
      'email' => channel(valid_rows.count { |row| row[:email].present? }),
      'whatsapp' => channel(valid_rows.count { |row| row[:normalized_phone].present? })
    }
  end

  def channel(count)
    { 'enabled' => count.positive?, 'count' => count }
  end

  def persist_rows(row_results)
    row_results.each do |row|
      valid = row[:errors].blank?
      campaign_import.campaign_import_rows.create!(
        row_number: row[:row_number], raw_name: row[:raw_name], raw_phone_masked: row[:raw_phone_masked],
        email_masked: row[:email_masked], company_name: row[:company_name], extra_values: row[:extra_values],
        normalized_name: valid ? row[:normalized_name] : nil,
        normalized_phone_hash: valid ? row[:normalized_phone_hash] : nil,
        normalized_email_hash: valid ? row[:email_hash] : nil,
        batch_index: row[:batch_index], status: valid ? :valid : :invalid, error_messages: row[:errors]
      )
    end
  end

  def attach_normalized_csv(valid_rows)
    rows = valid_rows.map do |row|
      {
        'row_number' => row[:row_number], 'name' => row[:normalized_name],
        'phone_number' => row[:normalized_phone], 'phone_hash' => row[:normalized_phone_hash],
        'email' => row[:email], 'email_hash' => row[:email_hash],
        'company_name' => row[:company_name], 'batch_index' => row[:batch_index]
      }
    end
    attach_csv(campaign_import.normalized_csv, AUDIENCE_NORMALIZED_HEADERS, rows, 'normalized')
  end

  def attach_error_csv(global_errors, row_results)
    rows = row_results.select { |row| row[:errors].present? }.map do |row|
      { 'row_number' => row[:row_number], 'name' => row[:raw_name], 'phone_number' => row[:raw_phone_masked],
        'email' => row[:email_masked], 'errors' => row[:errors].join(';') }
    end
    rows << { 'row_number' => '', 'errors' => global_errors.join(';') } if global_errors.present?
    attach_csv(campaign_import.error_csv, AUDIENCE_ERROR_HEADERS, rows, 'errors')
  end

  def attach_csv(attachment, headers, rows, suffix)
    attachment.attach(
      io: StringIO.new(CampaignImports::CsvSanitizer.generate(headers, rows)), filename: normalized_filename(suffix), content_type: 'text/csv'
    )
  end
end
