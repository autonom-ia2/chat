json.id resource.id
json.status resource.status
json.undo_status resource.undo_status
json.campaign_name resource.campaign_name
json.name resource.name
json.flow resource.audience? ? CampaignImport::AUDIENCE_FLOW : 'campaign_base'
json.channels resource.channels || {}
json.extra_columns resource.extra_columns || []
json.schema_resolution resource.schema_resolution || {}
json.create_companies resource.create_companies?
json.companies do
  json.created resource.companies_created_count
  json.reused resource.companies_reused_count
  json.contacts_linked resource.company_contacts_linked_count
  json.kept resource.companies_kept_count
end
json.campaign_slug resource.campaign_slug
json.base_label resource.base_label
json.mode resource.mode
json.batch_count resource.batch_count
json.source_filename resource.source_filename
json.source_format resource.source_format
json.source_byte_size resource.source_byte_size
json.total_rows resource.total_rows
json.valid_rows resource.valid_rows
json.invalid_rows resource.invalid_rows
json.imported_contacts_count resource.imported_contacts_count
json.existing_contacts_count resource.existing_contacts_count
json.failed_contacts_count resource.failed_contacts_count
json.validation_summary resource.validation_summary || {}
json.labels_payload resource.labels_payload || {}
json.can_delete resource.deletable?
json.created_at resource.created_at
json.updated_at resource.updated_at
json.validated_at resource.validated_at
json.confirmed_at resource.confirmed_at
json.import_started_at resource.import_started_at
json.import_finished_at resource.import_finished_at
json.undo_started_at resource.undo_started_at
json.undo_finished_at resource.undo_finished_at

json.created_by do
  json.id resource.user_id
  json.name resource.user&.name
end

json.downloads do
  json.original resource.original_file.attached?
  json.normalized_csv resource.normalized_csv.attached?
  json.error_csv resource.error_csv.attached?
  json.report_csv resource.report_csv.attached?
end

json.labels do
  json.array! resource.campaign_import_labels.sort_by { |label| [label.kind, label.batch_index || -1, label.title] } do |label|
    json.id label.id
    json.label_id label.label_id
    json.title label.title
    json.kind label.kind
    json.batch_index label.batch_index
    json.planned_count label.planned_count
    json.applied_count label.applied_count
  end
end
