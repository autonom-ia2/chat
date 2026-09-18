class CreateEmailProtectionMaintenanceRuns < ActiveRecord::Migration[7.1]
  def up
    create_table :email_protection_maintenance_runs do |table|
      identity_columns(table)
      progress_columns(table)
      lease_columns(table)
      table.timestamps
    end
    add_index :email_protection_maintenance_runs, [:account_id, :idempotency_key], unique: true, name: 'idx_email_maintenance_idempotency'
    add_index :email_protection_maintenance_runs, [:status, :next_dispatch_at], name: 'idx_email_maintenance_dispatch'
    add_check_constraint :email_protection_maintenance_runs, 'batch_size BETWEEN 1 AND 500', name: 'email_maintenance_batch_bound'
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Retain maintenance history and suppressions; roll back code and flags only'
  end

  private

  def identity_columns(table)
    table.references :account, null: false, foreign_key: { on_delete: :cascade }
    # Logical attribution only: removing an operator must remain possible.
    table.bigint :actor_id
    table.string :reason, null: false, limit: 200
    table.string :idempotency_key, null: false, limit: 100
    table.boolean :dry_run, null: false, default: true
    table.integer :batch_size, null: false, default: 100
  end

  def progress_columns(table)
    table.string :status, null: false, default: 'pending'
    table.string :phase, null: false, default: 'events'
    table.bigint :event_horizon, null: false
    table.bigint :legacy_horizon, null: false
    table.bigint :event_cursor, null: false, default: 0
    table.bigint :legacy_cursor, null: false, default: 0
    table.jsonb :counts, null: false, default: {}
  end

  def lease_columns(table)
    table.string :lease_token
    table.datetime :lease_expires_at
    table.datetime :next_dispatch_at, null: false
    table.integer :retry_count, null: false, default: 0
    table.integer :attempts, null: false, default: 0
    table.integer :enqueue_attempts, null: false, default: 0
    table.integer :error_count, null: false, default: 0
    table.string :error_code
    table.datetime :started_at
    table.datetime :finished_at
  end
end
