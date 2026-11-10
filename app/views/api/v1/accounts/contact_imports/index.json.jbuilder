# Contatos > Importações (#2771): one line per import, counts only. No file name (GET /:id has it), row or contact data.
json.payload do
  json.array! @campaign_imports do |campaign_import|
    json.id campaign_import.id
    json.status campaign_import.status
    json.origin campaign_import.from_automation? ? 'automation' : 'file'
    json.name campaign_import.name
    json.total_rows campaign_import.total_rows
    json.imported_contacts_count campaign_import.imported_contacts_count
    json.failed_count campaign_import.failed_contacts_count + campaign_import.invalid_rows
    json.created_at campaign_import.created_at
    json.created_by do
      json.id campaign_import.user_id
      json.name campaign_import.user&.name
    end
  end
end

json.meta do
  json.count @campaign_imports_count
  json.current_page @current_page
  json.per_page Api::V1::Accounts::ContactImportsController::RESULTS_PER_PAGE
end
