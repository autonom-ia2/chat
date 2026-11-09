json.id recipient.id
json.email_campaign_id recipient.email_campaign_id
# #2802: who does not read contacts sees the name and e-mail masked (ConversationAudience::Access).
json.name @contact_data_hidden ? ConversationAudience::Access.masked_name(recipient.name) : recipient.name
json.email @contact_data_hidden ? ConversationAudience::Access.masked_email(recipient.email) : recipient.email
json.status recipient.status
json.ses_message_id recipient.ses_message_id
json.sent_at recipient.sent_at
json.last_error recipient.last_error
json.created_at recipient.created_at
