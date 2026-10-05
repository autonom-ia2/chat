# Importar contatos (#1006, PRD §8.7): which contact custom attribute each extra column of the
# spreadsheet fills. Read-only; used by the preview (before saving) and by the import.
#
# - A column whose header names an existing contact attribute (same key, or same display name
#   once normalized) fills that attribute.
# - Any other column gets a new key from its header (CampaignImports::HeaderMapper.normalize_key:
#   accents removed, lowercase, spaces become "_"); the import creates it as a text attribute
#   with the header as its display name, so it shows on the contact page. The screen lists
#   these as new before the person saves.
# - A key never repeats within the file and never takes a standard contact field (name, email,
#   city...): it gets "_2", "_3"...
class ContactImports::AttributeColumns
  Column = Struct.new(:column, :key, :label, :existing, :definition, keyword_init: true) do
    def type = definition&.attribute_display_type || 'text'

    # Values of a typed attribute are converted, and left out when they do not fit (AttributeValue).
    def cast(raw) = type == 'text' ? raw : ContactImports::AttributeValue.new(definition).cast(raw)

    def to_h = { 'column' => column, 'key' => key, 'label' => label, 'existing' => existing, 'type' => type }
  end

  RESERVED_KEYS = CustomAttributeDefinition::STANDARD_ATTRIBUTES[:contact]
  FALLBACK_KEY = 'coluna'.freeze

  def initialize(account, extra_columns)
    @account = account
    @extra_columns = Array(extra_columns)
  end

  def perform
    used = []
    @extra_columns.map do |header|
      column = existing_column(header, used) || new_column(header, used)
      used << column.key
      column
    end
  end

  def self.normalize(text)
    CampaignImports::HeaderMapper.normalize_key(text.to_s)
  end

  private

  def existing_column(header, used)
    definition = definitions_by_key[self.class.normalize(header)] || definitions_by_label[self.class.normalize(header)]
    return if definition.nil? || used.include?(definition.attribute_key)

    Column.new(column: header, key: definition.attribute_key, label: definition.attribute_display_name, existing: true, definition: definition)
  end

  def new_column(header, used)
    base = self.class.normalize(header).presence || FALLBACK_KEY
    taken = used + RESERVED_KEYS + definitions_by_key.keys
    key = taken.include?(base) ? (2..).lazy.map { |number| "#{base}_#{number}" }.find { |candidate| taken.exclude?(candidate) } : base
    Column.new(column: header, key: key, label: header.to_s.strip, existing: false)
  end

  def definitions
    @definitions ||= @account.custom_attribute_definitions.contact_attribute.to_a
  end

  def definitions_by_key
    @definitions_by_key ||= definitions.index_by(&:attribute_key)
  end

  def definitions_by_label
    @definitions_by_label ||= definitions.each_with_object({}) do |definition, index|
      index[self.class.normalize(definition.attribute_display_name)] ||= definition
    end
  end
end
