conversation_visibility = local_assigns[:conversation_visibility] || Crm::Conversations::Visibility.new(
  account: Current.account,
  user: Current.user,
  account_user: Current.account_user
)
conversation_visible = follow_up.conversation.blank? || conversation_visibility.visible?(follow_up.conversation)

safe_contact = follow_up.contact if [follow_up.card&.contact_id, follow_up.conversation&.contact_id].include?(follow_up.contact_id)
# Sem card (#1461), o contato foi escolhido por quem marcou: é o próprio lembrete.
safe_contact ||= follow_up.contact if follow_up.card_id.nil?
safe_inbox = follow_up.inbox if [follow_up.card&.inbox_id, follow_up.conversation&.inbox_id].include?(follow_up.inbox_id)
safe_assignee = follow_up.assignee if [follow_up.card&.owner_id, follow_up.conversation&.assignee_id].include?(follow_up.assignee_id)
safe_assignee ||= follow_up.assignee if Current.account_user&.administrator?

json.extract! follow_up, :id, :account_id, :card_id, :title, :description, :follow_up_type, :status, :automation_mode,
              :timezone
json.metadata follow_up.metadata.to_h.stringify_keys.except('send_error')
# #1590: o motivo de a mensagem não ter saído, como código, só com a flag crm_mensagem_marcada; o texto cru fica fora.
json.send_error_code Crm::FollowUps::SendErrorCode.for(follow_up) if Crm::FollowUps::SendErrorCode.enabled?(Current.account)
json.contact_id safe_contact&.id
json.inbox_id safe_inbox&.id
json.assignee_id safe_assignee&.id
json.conversation_id conversation_visible ? follow_up.conversation_id : nil
json.due_at follow_up.due_at&.iso8601
# #1460/#1462: a vez de uma série e quem recebe.
json.series_id follow_up.series_id
json.occurrence_at follow_up.occurrence_at&.iso8601
json.recipient_mode follow_up.recipient_mode
json.recipient_user_ids follow_up.recipient_user_ids
json.recipient_team_id follow_up.recipient_team_id
json.company_id follow_up.company_id
# Sem ver contatos, sem empresa (#1849, D7).
if follow_up.company.present? && Crm::Cards::ContactReading.full?(user: Current.user, account_user: Current.account_user)
  json.company { json.extract! follow_up.company, :id, :name }
end
if follow_up.series.present?
  json.series do
    json.extract! follow_up.series, :id, :frequency, :weekdays, :weekdays_only, :ends_mode, :ends_on, :occurrences_count,
                  :status, :timezone
    json.starts_at follow_up.series.starts_at&.iso8601
  end
end
json.completed_at follow_up.completed_at&.iso8601
json.canceled_at follow_up.canceled_at&.iso8601
json.created_at follow_up.created_at&.iso8601
json.updated_at follow_up.updated_at&.iso8601

if follow_up.card.present?
  json.card do
    json.id follow_up.card.id
    json.title follow_up.card.title
    json.pipeline_id follow_up.card.pipeline_id
    json.stage_id follow_up.card.stage_id
  end
end

if safe_contact.present?
  json.contact do
    json.id safe_contact.id
    json.name safe_contact.name
    json.phone_number safe_contact.phone_number
    json.email safe_contact.email
  end
end

if safe_inbox.present?
  json.inbox do
    json.id safe_inbox.id
    json.name safe_inbox.name
    json.channel_type safe_inbox.channel_type
  end
end

if safe_assignee.present?
  json.assignee do
    json.id safe_assignee.id
    json.name safe_assignee.name
    json.email safe_assignee.email
  end
end

if follow_up.created_by.present?
  json.created_by do
    json.id follow_up.created_by.id
    json.name follow_up.created_by.name
  end
end
