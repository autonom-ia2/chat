# Email in the campaign journey (#999, PRD §8.9 and §8.6), fork tables only:
# - email_campaigns.reply_to_inbox_id: "Respostas vão para a caixa X". The send uses that inbox's
#   address as Reply-To, so the reply becomes a conversation in it. Deleting the inbox clears it.
# - email_campaign_recipients.contact_id: the audience contact a recipient came from (nil for
#   recipients imported from a spreadsheet). Deleting the contact keeps the recipient's history.
class AddReplyToInboxAndContactToEmailCampaigns < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_reference :email_campaigns, :reply_to_inbox, null: true, index: { algorithm: :concurrently },
                                                     foreign_key: { to_table: :inboxes, on_delete: :nullify, validate: false }
    add_reference :email_campaign_recipients, :contact, null: true, index: { algorithm: :concurrently },
                                                        foreign_key: { on_delete: :nullify, validate: false }
  end
end
