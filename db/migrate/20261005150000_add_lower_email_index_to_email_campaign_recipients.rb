# #1002: an e-mail reply is matched to the campaigns that reached that address across campaigns
# (CampaignJourney::ReplyMarker). The existing unique index leads with email_campaign_id, so a
# lookup by address alone cannot use it. Fork table; built concurrently.
class AddLowerEmailIndexToEmailCampaignRecipients < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_index :email_campaign_recipients, 'lower((email)::text), sent_at',
              name: 'idx_email_campaign_recipients_lower_email_sent_at', algorithm: :concurrently, if_not_exists: true
  end
end
