# Importar contatos (#1006): a contact import draft built on the campaign import helpers.
module ContactImportHelpers
  def create_contact_import(account:, user:, content:, filename: 'contatos.csv', content_type: 'text/csv')
    campaign_import = create_campaign_import(account: account, user: user, content: content, filename: filename,
                                             batch_count: 1, content_type: content_type)
    campaign_import.update!(campaign_name: nil, mode: 'single_label', options: { 'flow' => CampaignImport::CONTACTS_FLOW })
    campaign_import
  end

  # Validates with the columns given, as the screen does after "Trocar".
  def validate_contact_import(campaign_import, mapping)
    campaign_import.update!(schema_resolution: { 'manual_mapping' => mapping, 'header_row' => 1, 'table_index' => 0 })
    ContactImports::Validator.new(campaign_import).perform
    campaign_import.reload
  end

  def import_contacts!(campaign_import)
    campaign_import.update!(status: :queued)
    CampaignImports::Importer.new(campaign_import).perform
    campaign_import.reload
  end
end

RSpec.configure do |config|
  config.include ContactImportHelpers
end
