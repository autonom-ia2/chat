json.id resource.id
json.account_id resource.account_id
json.inbox_id resource.inbox_id
json.title resource.title
json.status resource.status
json.audience resource.audience
json.message_body resource.message_body
json.template_snapshot resource.template_snapshot
json.media_snapshot resource.media_snapshot
json.recipients_count resource.recipients_count
json.sent_count resource.sent_count
json.failed_count resource.failed_count
json.cancelled_count resource.cancelled_count
json.opted_out_count resource.opted_out_count
json.last_error_message resource.last_error_message
json.scheduled_at resource.scheduled_at
json.started_at resource.started_at
json.paused_at resource.paused_at
json.resumed_at resource.resumed_at
json.completed_at resource.completed_at
json.cancelled_at resource.cancelled_at
json.created_at resource.created_at
json.updated_at resource.updated_at

if resource.inbox.present?
  json.inbox do
    json.id resource.inbox.id
    json.name resource.inbox.name
    json.channel_type resource.inbox.channel_type
  end
end

if resource.created_by.present?
  json.created_by do
    json.id resource.created_by.id
    json.name resource.created_by.name
  end
end
