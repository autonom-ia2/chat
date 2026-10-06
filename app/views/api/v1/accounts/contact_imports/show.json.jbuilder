json.payload do
  json.partial! 'api/v1/models/campaign_import', formats: [:json], resource: @campaign_import
  # The first rows left out, with the reasons; phone and e-mail already masked, no name.
  json.problem_rows @campaign_import.campaign_import_rows.status_invalid.order(:row_number)
                                    .limit(Api::V1::Accounts::ContactImportsController::PROBLEM_ROWS_SHOWN) do |row|
    json.row_number row.row_number
    json.phone row.raw_phone_masked
    json.email row.email_masked
    json.errors row.error_messages
  end
end
