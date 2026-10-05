# The columns a person picked for an audience (PATCH .../columns, Públicos #992): each target
# is a column index of the header the reader found, or nil. Indices must exist and be distinct,
# and a phone or an email column is required. Returns nil when the choice is not usable.
class CampaignImports::ColumnChoice
  TARGETS = CampaignImports::SpreadsheetReader::TARGETS
  CONTACT_TARGETS = CampaignImports::SpreadsheetReader::CONTACT_TARGETS

  def initialize(raw, column_count:)
    @raw = raw.to_h.stringify_keys
    @column_count = column_count
  end

  def mapping
    mapping = TARGETS.index_with { |target| index_for(@raw[target]) }
    return if TARGETS.any? { |target| @raw[target].present? && mapping[target].nil? }

    indices = mapping.values.compact
    return unless indices.uniq == indices && mapping.values_at(*CONTACT_TARGETS).any?

    mapping
  end

  private

  def index_for(value)
    index = Integer(value.to_s, exception: false) if value.present?
    index if index&.between?(0, @column_count - 1)
  end
end
