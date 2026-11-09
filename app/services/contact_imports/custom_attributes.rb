# Importar contatos (#1006): writes the extra columns of a row as contact custom attributes.
#
# prepare! runs once before the rows: it creates the text attributes the preview listed as new
# (ContactImports::AttributeColumns), so the values show on the contact page. merge! runs
# inside each row savepoint: a contact gains the values it does not have yet; a value it
# already has is kept, the same rule as name, phone and email (ContactBlankFields).
#
# The automation step "para_cada" (#2771, G24) writes the extra fields of each item the same way, with the field keys
# as the column headers and no import record (`for_columns`).
class ContactImports::CustomAttributes
  def self.for_columns(account, extra_columns) = new(nil, account: account, extra_columns: extra_columns)

  def initialize(campaign_import, account: campaign_import.account, extra_columns: campaign_import.extra_columns)
    @campaign_import = campaign_import
    @account = account
    @extra_columns = extra_columns
  end

  # Returns how many attributes it created.
  def prepare!
    created = columns.reject(&:existing).count { |column| create_definition(column) }
    @campaign_import&.update!(validation_summary: @campaign_import.validation_summary.to_h.merge('contact_attributes_created' => created))
    created
  end

  # extra_values: { 'Vencimento' => '10/2026' } as stored on the import row (blank cells left out).
  # A value that does not fit a typed attribute (number, date, list...) is left out; the preview
  # already listed it (ContactImports::AttributeProblems).
  #
  # The contact is locked and read again first: two writers on the same contact (two automation runs, #2771) would
  # otherwise each write the whole hash they read before, and the last one would drop the keys the other just wrote.
  def merge!(contact, extra_values)
    return if extra_values.blank?

    contact.with_lock do
      current = contact.custom_attributes.to_h
      additions = additions(current, extra_values)
      contact.update!(custom_attributes: current.merge(additions)) if additions.any?
    end
  end

  private

  def additions(current, extra_values)
    extra_values.to_h.each_with_object({}) do |(header, raw), found|
      column = columns_by_header[header]
      next if column.nil? || raw.blank? || current[column.key].to_s.strip.present?

      value = column.cast(raw)
      found[column.key] = value unless value == ContactImports::AttributeValue::INVALID
    end
  end

  def columns
    @columns ||= ContactImports::AttributeColumns.new(@account, @extra_columns).perform
  end

  def columns_by_header
    @columns_by_header ||= columns.index_by(&:column)
  end

  # Another import or a person may create the same key between the lookup and the insert: the
  # unique index wins, the existing attribute is used and the import goes on.
  def create_definition(column)
    scope = @account.custom_attribute_definitions.where(attribute_model: :contact_attribute)
    return false if scope.exists?(attribute_key: column.key)

    scope.create!(attribute_key: column.key, attribute_display_name: column.label, attribute_display_type: :text)
    true
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => e
    raise if e.is_a?(ActiveRecord::RecordInvalid) && !e.record.errors.of_kind?(:attribute_key, :taken)

    scope.find_by!(attribute_key: column.key)
    false
  end
end
