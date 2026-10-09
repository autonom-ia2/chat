class CreateEmailReputationStates < ActiveRecord::Migration[7.1]
  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength -- keep the additive schema together
  def change
    create_table :email_reputation_states do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.bigint :observation_generation, null: false, default: 0
      t.bigint :feedback_version, null: false, default: 0
      t.bigint :evaluated_feedback_version, null: false, default: 0
      t.datetime :evaluation_lease_until
      t.string :evaluation_lease_token
      t.boolean :blocked, null: false, default: false
      t.string :level, null: false, default: 'unknown'
      t.jsonb :current_metrics, null: false, default: {}
      t.jsonb :policy, null: false, default: {}
      t.datetime :evaluated_at
      t.datetime :triggered_at
      t.jsonb :trigger_snapshot, null: false, default: {}
      t.jsonb :override, null: false, default: {}
      t.timestamps
    end
    create_table :email_reputation_audits do |t|
      t.references :account, null: true
      t.string :provider_key
      t.string :action, null: false
      t.bigint :actor_id
      t.jsonb :snapshot, null: false, default: {}
      t.datetime :created_at, null: false
    end
    add_index :email_reputation_audits, [:account_id, :created_at], name: 'idx_email_reputation_audits_account_time'
    create_table :email_provider_states do |t|
      t.string :provider_key, null: false
      t.string :status, null: false, default: 'unknown'
      t.boolean :blocked, null: false, default: false
      t.boolean :manual_block, null: false, default: false
      t.string :manual_reason
      t.jsonb :telemetry, null: false, default: {}
      t.datetime :observed_at
      t.datetime :checked_at
      t.string :error_code
      t.timestamps
    end
    add_index :email_provider_states, :provider_key, unique: true
    add_column :email_campaigns, :pause_reason, :jsonb, null: false, default: {}
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
end
