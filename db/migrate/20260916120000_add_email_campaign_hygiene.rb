class AddEmailCampaignHygiene < ActiveRecord::Migration[7.1]
  def up
    create_suppression_states
    create_suppression_events
    add_preflight_fields
    create_import_issues
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Retain suppression state and audit; roll back code/mode instead'
  end

  private

  def create_suppression_states
    # Legacy email_suppressions is intentionally untouched: permanent positives only.
    create_table :email_suppression_states do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.string :email, null: false
      t.boolean :active, null: false, default: false
      t.string :reason
      t.string :source
      t.datetime :expires_at
      t.datetime :first_seen_at
      t.datetime :last_seen_at
      t.integer :occurrences, null: false, default: 0
      t.bigint :origin_campaign_id
      t.datetime :created_at, null: false
    end
    add_index :email_suppression_states, [:account_id, :email], unique: true, name: 'idx_suppression_states_account_email'
    add_check_constraint :email_suppression_states, 'email = lower(btrim(email))', name: 'suppression_state_normalized_email'
  end

  def create_suppression_events
    create_table :email_suppression_events do |t|
      # Logical audit references survive an authorized account/state deletion.
      # No restrictive foreign key may turn normal account removal into a partial failure.
      t.references :email_suppression_state, null: false
      t.references :account, null: false
      t.bigint :origin_campaign_id
      t.string :event_key, null: false, limit: 200
      t.string :action, null: false
      t.string :reason, null: false
      t.string :source, null: false
      t.datetime :occurred_at, null: false
      t.datetime :first_seen_at, null: false
      t.datetime :last_seen_at, null: false
      t.jsonb :metadata, null: false, default: {}
      t.datetime :created_at, null: false
    end
    add_index :email_suppression_events, [:account_id, :email_suppression_state_id, :event_key],
              unique: true, name: 'idx_suppression_events_replay'
    add_index :email_suppression_events, [:email_suppression_state_id, :reason, :occurred_at], name: 'idx_suppression_events_window'
  end

  def add_preflight_fields
    change_table :email_campaign_recipients, bulk: true do |t|
      t.string :preflight_status, null: false, default: 'unchecked'
      t.string :preflight_reason_code
      t.string :preflight_suggestion, limit: 320
      t.datetime :preflight_checked_at
      t.datetime :preflight_valid_until
    end
    change_table :email_campaigns, bulk: true do |t|
      t.string :hygiene_pause_reason
      t.jsonb :preflight_summary, null: false, default: {}
      t.string :preflight_lease_token
      t.datetime :preflight_lease_expires_at
      t.bigint :preflight_cursor, null: false, default: 0
      t.bigint :preflight_ceiling, null: false, default: 0
    end
  end

  def create_import_issues
    create_table :email_campaign_import_issues do |t|
      t.references :email_campaign, null: false, foreign_key: true
      t.references :email_campaign_import, foreign_key: true
      t.integer :row_number, null: false
      t.string :raw_address, null: false, limit: 320
      t.string :reason_code, null: false
      t.string :suggestion, limit: 320
      t.datetime :created_at, null: false
    end
    add_index :email_campaign_import_issues, [:email_campaign_import_id, :row_number], unique: true, name: 'idx_import_issues_row'
  end
end
