# Importar contatos (#1006): writes the extra columns of a row as contact custom attributes.
#
# prepare! runs once before the rows: it creates the text attributes the preview listed as new
# (ContactImports::AttributeColumns), so the values show on the contact page. merge! runs
# inside each row savepoint: a contact gains the values it does not have yet; a value it
# already has is kept, the same rule as name, phone and email (ContactBlankFields).
class ContactImports::CustomAttributes
  def initialize(campaign_import)
    @campaign_import = campaign_import
    @account = campaign_import.account
  end

  # Returns how many attributes it created.
  def prepare!
    created = columns.reject(&:existing).count { |column| create_definition(column) }
    @campaign_import.update!(validation_summary: @campaign_import.validation_summary.to_h.merge('contact_attributes_created' => created))
    created
  end

  # extra_values: { 'Vencimento' => '10/2026' } as stored on the import row (blank cells left out).
  def merge!(contact, extra_values)
    current = contact.custom_attributes.to_h
    additions = extra_values.to_h.each_with_object({}) do |(header, value), found|
      key = keys_by_header[header]
      found[key] = value if key && current[key].blank? && value.present?
    end
    contact.update!(custom_attributes: current.merge(additions)) if additions.any?
  end

  private

  def columns
    @columns ||= ContactImports::AttributeColumns.new(@account, @campaign_import.extra_columns).perform
  end

  def keys_by_header
    @keys_by_header ||= columns.to_h { |column| [column.column, column.key] }
  end

  def create_definition(column)
    definition = @account.custom_attribute_definitions.find_or_initialize_by(attribute_model: :contact_attribute, attribute_key: column.key)
    return false if definition.persisted?

    definition.assign_attributes(attribute_display_name: column.label, attribute_display_type: :text)
    definition.save!
    true
  end
end
