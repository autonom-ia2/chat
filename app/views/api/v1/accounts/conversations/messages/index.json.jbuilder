json.meta do
  json.labels @conversation.cached_label_list_array
  json.additional_attributes Crm::AnuncioDeOrigem.atributos_para(Current.user, Current.account_user, @conversation.additional_attributes) # #2271
  json.contact @conversation.contact.push_event_data
  json.assignee @conversation.assignee.push_event_data if @conversation.assignee.present?
  json.agent_last_seen_at @conversation.agent_last_seen_at
  json.assignee_last_seen_at @conversation.assignee_last_seen_at
end

json.payload do
  json.array! @messages do |message|
    json.partial! 'api/v1/models/message', message: message
  end
end
