json.payload do
  json.array! @agent_inboxes do |agent_inbox|
    json.id agent_inbox.id
    json.inbox_id agent_inbox.inbox_id
    json.inbox_name agent_inbox.inbox.name
    json.channel_type agent_inbox.inbox.channel_type
    json.connected_at agent_inbox.created_at
    json.has_schedule @has_schedule_by_inbox_id.fetch(agent_inbox.inbox_id, false)
  end
end

json.eligible_inboxes do
  json.array! @eligible_inboxes do |inbox|
    json.id inbox.id
    json.name inbox.name
    json.channel_type inbox.channel_type
    json.has_schedule @has_schedule_by_inbox_id.fetch(inbox.id, false)
  end
end

json.occupied_inboxes do
  json.array! @occupied_inboxes do |entry|
    inbox = entry.fetch(:inbox)
    json.id inbox.id
    json.name inbox.name
    json.channel_type inbox.channel_type
    json.occupied_by entry.fetch(:occupied_by)
  end
end
