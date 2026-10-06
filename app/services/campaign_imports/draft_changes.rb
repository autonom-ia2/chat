# What a person may change on a spreadsheet import before saving it (Públicos #992/#998 and
# Importar contatos #1006): the columns and the "Criar e ligar" switch. Each change runs under
# the import's lock and returns nil, or the error code when the import no longer allows it.
class CampaignImports::DraftChanges
  COLUMN_CHOICE_STATUSES = %w[needs_column_choice ready_to_confirm validation_failed].freeze
  COMPANIES_CHOICE_STATUSES = %w[uploaded validating needs_column_choice ready_to_confirm validation_failed].freeze

  def initialize(campaign_import)
    @campaign_import = campaign_import
  end

  # mapping: { 'name' => 0, 'phone' => 1, 'email' => nil, 'company' => 2 } (CampaignImports::ColumnChoice).
  # The caller enqueues CampaignImports::ValidateJob when it returns nil.
  def choose_columns(mapping)
    change(COLUMN_CHOICE_STATUSES, 'campaign_import.column_choice_not_available') do
      @campaign_import.update!(
        status: :validating, schema_resolution: @campaign_import.schema_resolution.to_h.merge('manual_mapping' => mapping)
      )
    end
  end

  # Only before saving: the importer reads the switch once the import is queued.
  def choose_companies(enabled)
    change(COMPANIES_CHOICE_STATUSES, 'campaign_import.companies_choice_not_available') do
      @campaign_import.update!(options: @campaign_import.options.to_h.merge('create_companies' => enabled))
    end
  end

  private

  def change(statuses, error_code)
    allowed = false
    @campaign_import.with_lock do
      @campaign_import.reload
      allowed = statuses.include?(@campaign_import.status)
      yield if allowed
    end
    allowed ? nil : error_code
  end
end
