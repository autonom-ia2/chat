# Campaign ↔ audience link (#1005, PRD §8.0-4 and §8.6): a fork table instead of a
# campaign_import_id column on Chatwoot's campaigns. One link per campaign (any engine,
# keyed by campaign_type + campaign_id). Deleting an audience detaches its links
# (campaign_import_id becomes NULL) so the campaign and its results stay.
# The message variables chosen in the journey live on the link (variable_bindings /
# variable_defaults): they only exist for a campaign that sends to an audience.
class CreateCampaignAudienceLinks < ActiveRecord::Migration[7.1]
  def change
    create_table :campaign_audience_links do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.string :campaign_type, null: false
      t.bigint :campaign_id, null: false
      t.references :campaign_import, null: true, foreign_key: { on_delete: :nullify }, index: true
      t.jsonb :variable_bindings, null: false, default: {}
      t.jsonb :variable_defaults, null: false, default: {}
      t.timestamps
    end

    add_index :campaign_audience_links, %i[campaign_type campaign_id], unique: true
  end
end
