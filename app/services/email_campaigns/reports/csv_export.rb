require 'csv'

class EmailCampaigns::Reports::CsvExport
  BATCH_SIZE = 500
  RECIPIENT_COLUMNS = %i[id name email status attempts last_event_at opens clicks delivery_outcome reason_code
                         preflight_status preflight_reason preflight_suggestion suppression_reason sent_at].freeze
  ISSUE_COLUMNS = %i[row_number raw_email reason_code suggestion].freeze

  def self.safe_cell(value)
    return value unless value.is_a?(String)

    # Spreadsheet engines can ignore whitespace/control characters before formulas.
    value.match?(/\A[[:space:][:cntrl:]]*[=+\-@]/) ? "'#{value}" : value
  end

  def initialize(scope:, columns:, &present)
    @scope = scope
    @columns = columns
    @present = present
    # Resolve parameters, authorization and the ID horizon before sending headers.
    @max_id = relation.maximum(:id)
  end

  def each
    return enum_for(:each) unless block_given?

    yield "\uFEFF"
    yield CSV.generate_line(@columns)
    return unless @max_id

    last_id = 0
    loop do
      batch, rows = ActiveRecord::Base.uncached do
        records = relation.where(id: (last_id + 1)..@max_id).order(:id).limit(BATCH_SIZE).to_a
        [records, @present.call(records)]
      end
      break if batch.empty?

      rows.each { |row| yield serialize(row) }
      last_id = batch.last.id
    end
  end

  private

  def serialize(row)
    CSV.generate_line(@columns.map do |key|
      value = row[key]
      value = value.iso8601 if value.respond_to?(:iso8601)
      self.class.safe_cell(value)
    end)
  end

  # A query factory refreshes time-sensitive suppression predicates for each batch.
  def relation
    scope = @scope.is_a?(Proc) ? @scope.call : @scope
    scope.except(:order, :limit, :offset)
  end
end
