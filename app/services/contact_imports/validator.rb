# Importar contatos (#1006, PRD §8.7): validated exactly like an audience (same SpreadsheetReader,
# Jev rules, manual column choice, row checks and company preview), plus what only a contact
# import shows before saving: which custom attribute each extra column fills, which values stay
# out or are kept, and how many rows are contacts the account already has.
#
# Trazer minha lista (#2896) marks its imports with options['trazer']: those are read by ContactImports::Trazer::Validador,
# a subclass with the rules of that screen. Without the mark (this screen's old flow, the automation) nothing changes.
class ContactImports::Validator < CampaignImports::AudienceValidator
  CONTACT_TARGETS = CampaignImports::SpreadsheetReader::CONTACT_TARGETS

  def perform
    return super unless instance_of?(ContactImports::Validator) && campaign_import.options.to_h.key?('trazer')

    ContactImports::Trazer::Validador.new(campaign_import).perform
  end

  private

  # The extra columns that keep no value. None here; Trazer minha lista has "não guardar" (ContactImports::Trazer::Validador).
  def discarded_columns
    []
  end

  def ready_attributes(row_results, valid_rows, invalid_rows, plan)
    attributes = super
    columns = ContactImports::AttributeColumns.new(campaign_import.account, attributes[:extra_columns] - discarded_columns).perform
    existing = ContactImports::ExistingContacts.new(campaign_import.account, valid_rows)
    summary = attributes[:validation_summary].merge(
      contact_attributes: columns.map(&:to_h),
      attribute_problems: ContactImports::AttributeProblems.new(columns, valid_rows, existing.custom_attributes_by_row).perform,
      existing_contacts: existing.count
    )
    attributes.merge(validation_summary: summary)
  end
end
