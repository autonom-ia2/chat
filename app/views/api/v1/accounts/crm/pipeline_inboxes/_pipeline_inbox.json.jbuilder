json.extract! pipeline_inbox, :id, :account_id, :pipeline_id, :inbox_id, :default_stage_id,
              :auto_create_card, :created_by_id, :created_at, :updated_at
json.caixa_no_crm caixa_no_crm?(pipeline_inbox.inbox_id)

if pipeline_inbox.inbox
  json.inbox do
    json.extract! pipeline_inbox.inbox, :id, :name, :channel_type
  end
end

if pipeline_inbox.default_stage
  json.default_stage do
    json.extract! pipeline_inbox.default_stage, :id, :name, :position
  end
end
