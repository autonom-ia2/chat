json.id webhook.id
json.name webhook.name
json.url webhook.url
json.account_id webhook.account_id
json.subscriptions webhook.subscriptions
json.include_contact_pii webhook.include_contact_pii
# The signing secret is issued by the platform: admin or token_manage (#2027).
json.secret webhook.secret if Current.account_user&.permission_granted?('token_manage')
if webhook.inbox
  json.inbox do
    json.id webhook.inbox.id
    json.name webhook.inbox.name
  end
end
