# Importar contatos (#1006, PRD §8.7): validated exactly like an audience (same SpreadsheetReader,
# Jev rules, manual column choice, row checks and company preview), plus what only a contact
# import shows before saving: which custom attribute each extra column fills and how many rows
# are contacts the account already has.
class ContactImports::Validator < CampaignImports::AudienceValidator
  private

  def ready_attributes(row_results, valid_rows, invalid_rows, plan)
    attributes = super
    columns = ContactImports::AttributeColumns.new(campaign_import.account, attributes[:extra_columns]).perform
    summary = attributes[:validation_summary].merge(
      contact_attributes: columns.map(&:to_h),
      attribute_problems: ContactImports::AttributeProblems.new(columns, valid_rows).perform,
      existing_contacts: ContactImports::ExistingContacts.new(campaign_import.account, valid_rows).count
    )
    attributes.merge(validation_summary: summary)
  end
end
