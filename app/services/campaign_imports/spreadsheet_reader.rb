# The one spreadsheet reader for the campaign journey (Públicos, #992) and, later, "Importar
# contatos" (#1006). It finds the header row, then which column holds the person name, mobile
# phone, email and company; every other column becomes an extra column.
#
# Who decides the columns (schema_resolution['method']):
# - 'jev': Jev answered every target with confidence >= 0.8 and the import goes on alone;
# - 'deterministic': Jev is off, failed or was unsure. The known header aliases only PRE-FILL a
#   suggestion and the user must confirm the columns (needs_confirmation) — never a silent alias;
# - 'manual': the user chose the columns (explicit_mapping).
class CampaignImports::SpreadsheetReader
  Error = Class.new(StandardError)
  TARGETS = %w[name phone email company].freeze
  CONTACT_TARGETS = %w[phone email].freeze
  EVIDENCE = { 'phone' => :valid_phone_count, 'email' => :valid_email_count }.freeze
  MIN_CONFIDENCE = TypesafeAi::ImportSchemaResolver::MIN_MAPPING_CONFIDENCE
  SCHEMA_ACCEPTANCE_THRESHOLD = TypesafeAi::ImportSchemaResolver::SCHEMA_ACCEPTANCE_THRESHOLD
  HEADER_MAPPER_KEYS = { 'name' => :name, 'phone' => :phone_number, 'email' => :email }.freeze
  COMPANY_ALIASES = ['empresa', 'company', 'companhia', 'organizacao', 'razao social', 'nome da empresa'].freeze

  Result = Struct.new(:headers, :rows, :mapping, :extra_columns, :resolution, keyword_init: true) do
    def needs_column_choice?
      resolution.fetch('needs_confirmation')
    end
  end

  # explicit_mapping: { 'name' => Integer|nil, 'phone' => ..., 'email' => ..., 'company' => ... }
  # pinned_header: { header_row: 3, table_index: 0 } keeps the header found before the user chose the columns.
  def initialize(parsed, explicit_mapping: nil, pinned_header: {}, ai_resolver: nil, jev_enabled: CampaignImports::JevConfig.available?)
    @parsed = parsed
    @explicit_mapping = explicit_mapping&.to_h&.transform_keys(&:to_s)
    @pinned_header = pinned_header.to_h.symbolize_keys.slice(:header_row, :table_index)
    @ai_resolver = ai_resolver
    @jev_enabled = jev_enabled
  end

  def perform
    candidate = CampaignImports::HeaderLocator.new(@parsed).perform(**@pinned_header)
    raise Error, 'empty_file' if candidate.nil? || candidate.rows.empty?

    columns = column_profiles(candidate)
    targets, jev = @explicit_mapping ? manual_targets(candidate) : suggested_targets(candidate, columns)
    build_result(candidate, columns, targets, jev)
  rescue CampaignImports::HeaderLocator::Error => e
    raise Error, e.message
  end

  private

  def column_profiles(candidate)
    masked = CampaignImports::ColumnProfiler.new(candidate.table.rows)
                                            .profiles(candidate.headers.length, candidate.rows, candidate.header_index)
    candidate.headers.each_with_index.map do |header, index|
      values = column_values(candidate.rows, index)
      {
        index: index, header: header, non_blank_count: values.size,
        valid_phone_count: values.count { |value| CampaignImports::ContactValues.phone?(value) },
        valid_email_count: values.count { |value| CampaignImports::ContactValues.email?(value) },
        examples: masked.fetch(index).fetch(:examples)
      }
    end
  end

  def column_values(rows, index)
    rows.map { |row| row.values[index].to_s }
        .select { |value| CampaignImports::ContactValues.readable?(value) }
        .map(&:strip).reject(&:empty?)
  end

  def manual_targets(candidate)
    mapping = TARGETS.index_with { |target| @explicit_mapping[target] }
    raise Error, 'invalid_column_choice' unless valid_indices?(mapping.values.compact, candidate.headers.size)
    raise Error, 'missing_contact_column' if mapping.values_at(*CONTACT_TARGETS).all?(&:nil?)

    [mapping.transform_values { |index| target_entry(index, source: 'manual', confident: true) }, { 'status' => 'skipped' }]
  end

  def valid_indices?(indices, column_count)
    indices.all? { |index| index.is_a?(Integer) && index.between?(0, column_count - 1) } && indices.uniq == indices
  end

  def suggested_targets(candidate, columns)
    jev = jev_answer(candidate, columns)
    answered = TARGETS.index_with { |target| confident_jev_entry(jev, target, columns) }
    repeated = answered.values.filter_map { |entry| entry&.fetch('column') }.tally.select { |_index, count| count > 1 }.keys
    confident = answered.transform_values { |entry| entry && repeated.exclude?(entry['column']) ? entry : nil }
    [with_suggestions(confident, jev, alias_mapping(candidate.headers)), jev.except('targets')]
  end

  def confident_jev_entry(jev, target, columns)
    answer = jev.dig('targets', target.to_sym)
    return unless answer && jev['schema_probability'].to_f > SCHEMA_ACCEPTANCE_THRESHOLD && answer[:confidence] >= MIN_CONFIDENCE

    index = answer[:index]
    return if index && EVIDENCE[target] && columns.fetch(index).fetch(EVIDENCE[target]).zero?

    target_entry(index, source: 'jev', confident: true, confidence: answer[:confidence])
  end

  # Unsure targets get a suggestion (alias first, then Jev's unsure pick) for the user to confirm.
  def with_suggestions(targets, jev, aliases)
    TARGETS.reduce(targets) do |current, target|
      next current if current[target]

      taken = current.values.filter_map { |entry| entry&.fetch('column') }
      current.merge(target => suggestion(jev.dig('targets', target.to_sym), aliases[target], taken))
    end
  end

  def suggestion(answer, alias_index, taken)
    options = [[alias_index, 'alias', nil], [answer&.dig(:index), 'jev', answer&.dig(:confidence)]]
    index, source, confidence = options.find { |option_index, _source, _confidence| option_index && taken.exclude?(option_index) }
    return target_entry(nil, source: nil, confident: false) unless index

    target_entry(index, source: source, confident: false, confidence: confidence)
  end

  def alias_mapping(headers)
    mapping = CampaignImports::HeaderMapper.new(headers, mode: :phone).perform.mapping
    company_aliases = COMPANY_ALIASES.map { |item| CampaignImports::HeaderMapper.normalize(item) }
    HEADER_MAPPER_KEYS.transform_values { |key| mapping[key] }.merge(
      'company' => headers.index { |header| company_aliases.include?(CampaignImports::HeaderMapper.normalize(header)) }
    )
  end

  def jev_answer(candidate, columns)
    return { 'status' => 'disabled' } unless @jev_enabled

    answer = ai_resolver.resolve(
      headers: candidate.headers, header_row_number: candidate.header_row_number,
      profiles: columns.map { |column| column.slice(:non_blank_count, :valid_phone_count, :valid_email_count, :examples) }
    )
    { 'status' => 'answered', 'model' => answer[:model], 'schema_probability' => answer[:schema_probability], 'targets' => answer[:targets] }
  rescue TypesafeAi::AudienceSchemaResolver::Error => e
    { 'status' => 'failed', 'error' => e.message }
  end

  def ai_resolver
    @ai_resolver || TypesafeAi::AudienceSchemaResolver.new
  end

  def target_entry(index, source:, confident:, confidence: nil)
    { 'column' => index, 'source' => source, 'confident' => confident, 'confidence' => confidence }
  end

  def build_result(candidate, columns, targets, jev)
    targets = targets.transform_values { |entry| entry.merge('header' => entry['column'] && candidate.headers[entry['column']]) }
    mapping = targets.transform_values { |entry| entry['column'] }
    uncertain = targets.reject { |_target, entry| entry['confident'] }.keys
    needs_confirmation = uncertain.any? || mapping.values_at(*CONTACT_TARGETS).all?(&:nil?)
    extra_columns = extra_columns_for(columns, mapping.values.compact)
    Result.new(headers: candidate.headers, rows: candidate.rows, mapping: mapping, extra_columns: extra_columns,
               resolution: resolution_for(candidate, columns, targets, jev, needs_confirmation, uncertain))
  end

  def resolution_for(candidate, columns, targets, jev, needs_confirmation, uncertain) # rubocop:disable Metrics/ParameterLists -- one flat record
    {
      'version' => 1, 'method' => resolution_method(jev, needs_confirmation), 'needs_confirmation' => needs_confirmation,
      'uncertain_targets' => uncertain, 'format' => @parsed.format, 'table_index' => candidate.table_index,
      'table_name' => candidate.table.name, 'delimiter' => candidate.table.delimiter, 'header_row' => candidate.header_row_number,
      'jev' => jev, 'targets' => targets,
      'columns' => columns.map { |column| column_entry(column) }
    }
  end

  # example_masked (#993): the first example in the same masked format sent to Jev, never a value.
  def column_entry(column)
    column.except(:examples).merge(example_masked: column[:examples].first).transform_keys(&:to_s)
  end

  def resolution_method(jev, needs_confirmation)
    return 'manual' if @explicit_mapping
    return 'deterministic' if needs_confirmation

    jev['status'] == 'answered' ? 'jev' : 'deterministic'
  end

  # [{ 'index' => 3, 'key' => 'Vencimento' }]: the key is the header as written, unique within the file.
  def extra_columns_for(columns, taken)
    columns.each_with_object([]) do |column, extras|
      next if taken.include?(column[:index]) || (column[:header].blank? && column[:non_blank_count].zero?)

      base = column[:header].presence || "column_#{column[:index] + 1}"
      extras << { 'index' => column[:index], 'key' => unique_key(base, extras.pluck('key')) }
    end
  end

  def unique_key(base, used)
    return base if used.exclude?(base)

    (2..).lazy.map { |number| "#{base} (#{number})" }.find { |key| used.exclude?(key) }
  end
end
