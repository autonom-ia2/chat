json.payload do
  json.campaign do
    json.partial! 'api/v1/accounts/email_campaigns/campaigns/campaign', campaign: @campaign
  end
  json.recipients do
    json.array! @recipients, partial: 'api/v1/accounts/email_campaigns/recipients/recipient', as: :recipient
  end
  json.meta do
    json.count @recipients_count
    json.current_page @current_page.to_i
  end
  json.import_result @campaign.latest_recipient_import&.result.presence
end
