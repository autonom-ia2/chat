# Why a campaign is paused, who paused it and who resumed it (#1329, épico #1320). A fork table,
# polymorphic over the campaign engines (Chatwoot `Campaign` and the fork's `EmailCampaign`), so no
# Chatwoot table gets a column. A native campaign is "paused" while it has an open row
# (resumed_at IS NULL): its campaign_status stays `active` and Campaign#trigger! does not fire it.
# At most one open pause per campaign (partial unique index).
class CreateCampaignPauses < ActiveRecord::Migration[7.1]
  def change
    create_table :campaign_pauses do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.string :pausable_type, null: false
      t.bigint :pausable_id, null: false
      t.string :source, null: false
      t.string :reason_code, null: false
      t.jsonb :details, null: false, default: {}
      t.references :paused_by, null: true, foreign_key: { to_table: :users, on_delete: :nullify }, index: false
      t.datetime :paused_at, null: false
      t.references :resumed_by, null: true, foreign_key: { to_table: :users, on_delete: :nullify }, index: false
      t.datetime :resumed_at
      t.timestamps
    end

    add_index :campaign_pauses, %i[pausable_type pausable_id paused_at], name: 'idx_campaign_pauses_on_pausable'
    add_index :campaign_pauses, %i[pausable_type pausable_id], unique: true, where: 'resumed_at IS NULL',
                                                               name: 'idx_campaign_pauses_one_open'
  end
end
