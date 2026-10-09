class AddEmailRecipientPreflightIndex < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_index :email_campaign_recipients, [:email_campaign_id, :preflight_valid_until],
              name: 'idx_recipients_preflight_due', algorithm: :concurrently
    # Default DNS-disabled maintenance scans only unfinished work, not every checked row.
    add_index :email_campaign_recipients, [:email_campaign_id, :id],
              where: "status = 0 AND preflight_status = 'unchecked'",
              name: 'idx_recipients_preflight_unchecked', algorithm: :concurrently
  end
end
