json.payload do
  json.array! @agent_inboxes do |agent_inbox|
    json.id agent_inbox.id
    json.inbox_id agent_inbox.inbox_id
    json.inbox_name agent_inbox.inbox.name
    json.channel_type agent_inbox.inbox.channel_type
    json.connected_at agent_inbox.created_at
    json.papel agent_inbox.papel
  end
end

json.eligible_inboxes do
  json.array! @eligible_inboxes do |inbox|
    json.id inbox.id
    json.name inbox.name
    json.channel_type inbox.channel_type
  end
end
