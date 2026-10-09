json.per_page @per_page
json.total_entries @total_entries
json.current_page @current_page

json.audit_logs do
  json.array! @audit_logs do |audit_log|
    # The list renders neither the deleted body nor the message payload, and building the
    # latter loads the conversation, sender and attachments for every row.
    message_audit = audit_log.auditable_type == 'Message'
    json.id audit_log.id
    json.auditable_id audit_log.auditable_id
    json.auditable_type audit_log.auditable_type
    json.auditable message_audit ? nil : audit_log.auditable.try(:push_event_data)
    json.associated_id audit_log.associated_id
    json.associated_type audit_log.associated_type
    json.user_id   audit_log.user_id
    json.user_type audit_log.user_type
    json.username audit_log.username
    json.actor(type: audit_log.user&.class&.name || audit_log.user_type, id: audit_log.user_id,
               name: audit_log.user&.name.presence || audit_log.username)
    json.action audit_log.action
    json.audited_changes message_audit ? audit_log.audited_changes.except('content') : audit_log.audited_changes
    operation_keys = audit_log.audited_changes.to_h.fetch('operation_config', {}).keys
    json.operation_key operation_keys.one? ? operation_keys.first : nil
    json.operation_keys operation_keys
    json.version audit_log.version
    json.comment audit_log.comment
    json.request_uuid audit_log.request_uuid
    json.created_at audit_log.created_at.to_i
    ip_address_enabled = Current.account.feature_enabled?(:audit_log_ip_address)
    json.remote_address ip_address_enabled ? audit_log.remote_address : audit_log.masked_remote_address
    json.location audit_log.location unless ip_address_enabled
  end
end
