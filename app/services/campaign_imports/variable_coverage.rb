# Which audience rows can receive a message whose variables come from the audience columns
# (Públicos, #992, acceptance B1b): a valid row without a value for a used variable stays out
# with the reason "missing_variable" — unless a default text was chosen for that variable.
#
# mapping:  { '1' => { 'source' => 'name' }, '2' => { 'source' => 'extra', 'column' => 'Vencimento' } }
# defaults: { '2' => 'em breve' }
class CampaignImports::VariableCoverage
  Error = Class.new(StandardError)
  FIELD_COLUMNS = { 'name' => :normalized_name, 'company' => :company_name }.freeze
  ROW_STATUSES = %i[valid imported].freeze
  MAX_LISTED = 100

  Result = Struct.new(:included_count, :excluded_count, :excluded, :missing_by_variable, keyword_init: true)

  def initialize(campaign_import, mapping:, defaults: {})
    @campaign_import = campaign_import
    @mapping = mapping.to_h.transform_keys(&:to_s).transform_values { |source| source.is_a?(Hash) ? source.stringify_keys : {} }
    @defaults = defaults.to_h.transform_keys(&:to_s).transform_values { |text| text.to_s.strip }
  end

  def perform
    validate_mapping!
    included = 0
    excluded = []
    each_row do |row_number, values|
      missing = @mapping.keys.select { |key| values.fetch(key).blank? && @defaults[key].blank? }
      if missing.empty?
        included += 1
      else
        excluded << { row_number: row_number, missing: missing }
      end
    end
    build_result(included, excluded)
  end

  private

  def validate_mapping!
    @mapping.each_value do |source|
      known = FIELD_COLUMNS.key?(source['source']) ||
              (source['source'] == 'extra' && Array(@campaign_import.extra_columns).include?(source['column']))
      raise Error, 'invalid_variable_mapping' unless known
    end
  end

  def each_row
    @campaign_import.campaign_import_rows.where(status: ROW_STATUSES).order(:row_number)
                    .pluck(:row_number, :normalized_name, :company_name, :extra_values).each do |row_number, name, company, extra|
      fields = { 'name' => name, 'company' => company }
      values = @mapping.transform_values do |source|
        source['source'] == 'extra' ? extra.to_h[source['column']] : fields[source['source']]
      end
      yield row_number, values
    end
  end

  def build_result(included, excluded)
    Result.new(
      included_count: included, excluded_count: excluded.size, excluded: excluded.first(MAX_LISTED),
      missing_by_variable: excluded.flat_map { |row| row[:missing] }.tally
    )
  end
end
