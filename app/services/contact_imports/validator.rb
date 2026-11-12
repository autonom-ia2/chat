# Importar contatos (#1006, PRD §8.7): validated exactly like an audience (same SpreadsheetReader,
# Jev rules, manual column choice, row checks and company preview), plus what only a contact
# import shows before saving: which custom attribute each extra column fills, which values stay
# out or are kept, and how many rows are contacts the account already has.
#
# Trazer minha lista (#2896) marks its imports with options['trazer']. With the mark the import never stops to ask for
# the columns: the reader's suggestion is taken, the import goes on, and schema_resolution keeps `uncertain_targets`,
# which the screen shows as "duvidosa" for the person to change there (Relacionamentos::Trazer::Colunas). With no phone
# and no e-mail column there is nobody to bring, so the reading fails with `missing_contact_column`. A column the person
# marked "não guardar" (Relacionamentos::Trazer::Colunas.chaves_que_nao_guardam) keeps no value on the rows and stays
# out of the attribute preview. Without the mark (this screen's old flow, the automation) nothing changes.
class ContactImports::Validator < CampaignImports::AudienceValidator
  CONTACT_TARGETS = CampaignImports::SpreadsheetReader::CONTACT_TARGETS

  private

  def read(parsed_file)
    reading = super
    return reading unless trazer? && reading.needs_column_choice? && reading.mapping.values_at(*CONTACT_TARGETS).any?

    CampaignImports::SpreadsheetReader::Result.new(**reading.to_h, resolution: reading.resolution.merge('needs_confirmation' => false))
  end

  def mark_needs_column_choice
    trazer? ? mark_validation_failed(['missing_contact_column'], []) : super
  end

  def trazer?
    campaign_import.options.to_h.key?('trazer')
  end

  def extra_values(row)
    super.except(*discarded_columns)
  end

  def discarded_columns
    @discarded_columns ||= trazer? ? Relacionamentos::Trazer::Colunas.chaves_que_nao_guardam(campaign_import.options, @reading.extra_columns) : []
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
