class AddContactInboxToCampaignRecipients < ActiveRecord::Migration[7.1]
  # Fork (upgrade 4.19.1, #3119): campaign_recipients has production rows, so the index is built concurrently.
  disable_ddl_transaction!

  def change
    add_reference :campaign_recipients, :contact_inbox, index: { algorithm: :concurrently }
  end
end
