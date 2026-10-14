json.extract! inbox_setting, :id, :account_id, :inbox_id, :crm_enabled, :default_pipeline_id,
              :default_stage_id, :visibility_mode, :auto_create_card, :subject_ai_mode, :created_at, :updated_at

if inbox_setting.inbox
  json.inbox do
    json.extract! inbox_setting.inbox, :id, :name, :channel_type
  end
end

if inbox_setting.default_pipeline
  json.default_pipeline do
    json.extract! inbox_setting.default_pipeline, :id, :name
  end
end

if inbox_setting.default_stage
  json.default_stage do
    json.extract! inbox_setting.default_stage, :id, :name, :position
  end
end
