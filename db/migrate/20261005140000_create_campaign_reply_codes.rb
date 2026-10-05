# Campaign reply code (#1002, PRD §6.7 and §8.3 "Marca no CRM"): the #CODE a campaign carries
# in a "talk on WhatsApp" button, recognized by Ctwa::TrackedLinkAttributor exactly like a
# tracked link code. A fork table (PRD §8.0-4): one code per campaign (any engine, keyed by
# campaign_type + campaign_id), unique across the installation.
class CreateCampaignReplyCodes < ActiveRecord::Migration[7.1]
  def change
    create_table :campaign_reply_codes do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.string :campaign_type, null: false
      t.bigint :campaign_id, null: false
      t.string :code, null: false
      t.timestamps
    end

    add_index :campaign_reply_codes, %i[campaign_type campaign_id], unique: true
    add_index :campaign_reply_codes, :code, unique: true
  end
end
