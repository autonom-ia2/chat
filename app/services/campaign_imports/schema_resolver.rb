class CampaignImports::SchemaResolver
  Error = Class.new(StandardError)
  Result = Struct.new(:headers, :rows, :mapper, :metadata, keyword_init: true)

  HEADER_SCAN_LIMIT = 100
  PROFILE_SAMPLE_SIZE = 50
  EXAMPLE_COUNT = 3
  EXAMPLE_LENGTH = 80

  def initialize(parsed, ai_resolver: nil)
    @parsed = parsed
    @ai_resolver = ai_resolver
  end

  def perform
    candidates = build_candidates
    raise Error, 'empty_file' if candidates.empty?
    return resolve_with_ai(candidates) if ai_available?

    known = known_candidate(candidates)
    return build_result(known) if known

    candidate = best_ai_candidate(candidates) || candidates.first
    raise Error, candidate.fetch(:mapper).errors.first.presence || 'schema_not_resolved'
  end

  private

  def known_candidate(candidates)
    mapped = candidates.select { |candidate| candidate.fetch(:mapper).errors.empty? }
    known = mapped.select { |candidate| candidate_has_email_evidence?(candidate) }
    # Bad address values do not turn recognized columns into a missing header.
    known = mapped if known.empty? && candidates.none? { |candidate| candidate_has_email_evidence?(candidate) }
    best_known_candidate(known) unless known.empty?
  end

  def build_candidates
    tables.flat_map.with_index do |table, table_index|
      candidate_positions(table).map.with_index do |row_index, candidate_index|
        build_candidate(table, table_index, row_index, candidate_index)
      end
    end
  end

  def candidate_positions(table)
    table.rows.each_index
         .select { |index| header_candidate_row?(table.rows[index]) }
         .first(HEADER_SCAN_LIMIT)
  end

  def build_candidate(table, table_index, row_index, candidate_index)
    header_row = table.rows.fetch(row_index)
    headers = normalize_headers(header_row.values)
    data_rows = table.rows.drop(row_index + 1).reject { |row| row.values.all? { |value| blank_valid_value?(value.to_s) } }
    {
      id: "table_#{table_index}_candidate_#{candidate_index}", table_index: table_index,
      table_name: table.name, delimiter: table.delimiter, header_row_number: header_row.row_number,
      headers: headers, rows: data_rows,
      mapper: CampaignImports::HeaderMapper.new(headers, mode: :email).perform,
      profiles: column_profiles(headers.length, data_rows)
    }
  end

  def tables
    return @parsed.tables if @parsed.tables.present?

    header_row = CampaignImports::Parser::ParsedRow.new(row_number: 1, values: @parsed.headers)
    [CampaignImports::Parser::ParsedTable.new(name: nil, delimiter: nil, rows: [header_row, *@parsed.rows])]
  end

  def best_known_candidate(candidates)
    known_table_headers(candidates).max_by do |candidate|
      email_index = candidate.fetch(:mapper).mapping.fetch(:email)
      profile = candidate.fetch(:profiles).fetch(email_index)
      [profile.fetch(:email_like_count), profile.fetch(:non_blank_count), candidate.fetch(:rows).length,
       candidate.fetch(:mapper).mapping.key?(:name) ? 1 : 0, -candidate.fetch(:table_index),
       -candidate.fetch(:header_row_number)]
    end
  end

  def known_table_headers(candidates)
    email_aliases = CampaignImports::HeaderMapper::ALIASES.fetch(:email).map { |header| CampaignImports::HeaderMapper.normalize(header) }
    candidates.group_by { |candidate| candidate.fetch(:table_index) }.values.map do |table_candidates|
      table_candidates.max_by do |candidate|
        mapper = candidate.fetch(:mapper)
        header = candidate.fetch(:headers).fetch(mapper.mapping.fetch(:email))
        exact_email_header = email_aliases.include?(CampaignImports::HeaderMapper.normalize(header))
        [exact_email_header ? 1 : 0, mapper.mapping.key?(:name) ? 1 : 0, -candidate.fetch(:header_row_number)]
      end
    end
  end

  def resolve_with_ai(candidates)
    candidate = known_candidate(candidates) || best_ai_candidate(candidates)
    validate_ai_input!(candidate)
    resolution = ai_resolver.resolve(candidate.except(:mapper, :rows))
    mapper = CampaignImports::HeaderMapper.new(candidate.fetch(:headers), mode: :email).perform(
      explicit_mapping: { email: resolution.fetch(:email_index), name: resolution[:name_index] }
    )
    raise Error, mapper.errors.first if mapper.errors.any?

    build_result(candidate, mapper, 'jev', resolution.fetch(:metadata))
  rescue TypesafeAi::ImportSchemaResolver::Error => e
    raise Error, e.message
  end

  def validate_ai_input!(candidate)
    raise Error, 'missing_email_header' unless candidate
    raise Error, 'empty_file' if candidate.fetch(:rows).empty?
    if !candidate_has_email_evidence?(candidate) && candidate.fetch(:rows).none? { |row| row.values.any? { |value| email_like?(value.to_s.strip) } }
      raise Error, 'no_valid_emails'
    end
  end

  def ai_resolver
    @ai_resolver || TypesafeAi::ImportSchemaResolver.new
  end

  def best_ai_candidate(candidates)
    tables = candidates.select { |candidate| candidate_has_email_evidence?(candidate) }.group_by { |candidate| candidate.fetch(:table_index) }
    # Invalid recipient rows must not replace the original header sent to Jev.
    headers = tables.values.map { |group| group.min_by { |candidate| candidate.fetch(:header_row_number) } }
    headers.max_by { |candidate| ai_candidate_score(candidate) }
  end

  def candidate_has_email_evidence?(candidate)
    candidate.fetch(:profiles).any? { |profile| profile.fetch(:email_like_count).positive? }
  end

  def ai_candidate_score(candidate)
    strongest_email_profile = candidate.fetch(:profiles).map { |profile| profile.fetch(:email_like_count) }.max.to_i
    [strongest_email_profile, candidate.fetch(:headers).count(&:present?), candidate.fetch(:rows).length,
     -candidate.fetch(:table_index), -candidate.fetch(:header_row_number)]
  end

  def build_result(candidate, mapper = candidate.fetch(:mapper), method = 'deterministic', ai_metadata = {})
    metadata = {
      'method' => method, 'format' => @parsed.format,
      'table_index' => candidate.fetch(:table_index), 'header_row' => candidate.fetch(:header_row_number),
      'delimiter' => candidate[:delimiter],
      'email_column' => mapper.mapping[:email], 'name_column' => mapper.mapping[:name],
      'custom_columns' => mapper.extra_columns.values.sort
    }.compact.merge(ai_metadata)

    Result.new(headers: candidate.fetch(:headers), rows: candidate.fetch(:rows), mapper: mapper, metadata: metadata)
  end

  def ai_available?
    @ai_resolver.present? || (TypesafeAi::Config.enabled? && TypesafeAi::Config.configured?)
  end

  def column_profiles(column_count, rows)
    sample = profile_sample(rows)
    Array.new(column_count) do |index|
      values = profiled_values(sample, index)
      {
        non_blank_count: values.length,
        email_like_count: values.count { |value| email_like?(value) },
        examples: values.uniq.first(EXAMPLE_COUNT).map { |value| example_value(value) }
      }
    end
  end

  def example_value(value)
    return '[email address]' if email_like?(value)
    return '[malformed email address]' if value.include?('@')

    value.first(EXAMPLE_LENGTH)
  end

  def profile_sample(rows)
    return rows if rows.length <= PROFILE_SAMPLE_SIZE

    step = (rows.length - 1).fdiv(PROFILE_SAMPLE_SIZE - 1)
    Array.new(PROFILE_SAMPLE_SIZE) { |index| rows[(index * step).round] }.uniq
  end

  def profiled_values(rows, index)
    rows.filter_map do |row|
      value = row.values[index].to_s
      value.strip if profile_value?(value)
    end.reject(&:empty?)
  end

  def profile_value?(value)
    value.valid_encoding? && value.exclude?("\0")
  end

  def email_like?(value)
    EmailCampaigns::EmailNormalizer.normalize!(value)
    true
  rescue EmailCampaigns::EmailNormalizer::Error
    false
  end

  def normalize_headers(headers)
    Array(headers).map.with_index do |header, index|
      value = header.to_s.strip
      index.zero? ? value.delete_prefix("\uFEFF") : value
    end
  end

  def header_candidate_row?(row)
    values = row.values.map(&:to_s)
    valid_header_values?(values) && values.none? { |value| email_like?(value.strip) }
  end

  def valid_header_values?(values)
    values.present? && values.any? { |value| !blank_valid_value?(value) } && values.all? { |value| profile_value?(value) }
  end

  def blank_valid_value?(value)
    value.valid_encoding? && value.strip.empty?
  end
end
