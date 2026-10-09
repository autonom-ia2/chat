class IndexEmailReputationCohorts < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_index :email_campaign_recipients, [:email_campaign_id, :sent_at],
              where: 'sent_at IS NOT NULL', name: 'idx_email_reputation_sent_cohort', algorithm: :concurrently
  end
end
