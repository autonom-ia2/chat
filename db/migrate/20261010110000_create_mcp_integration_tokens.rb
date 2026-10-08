class CreateMcpIntegrationTokens < ActiveRecord::Migration[7.1]
  def change
    create_table :mcp_integration_tokens do |t|
      t.references :account, null: false, foreign_key: true
      t.references :custom_role, foreign_key: { to_table: :custom_roles, on_delete: :nullify }
      t.references :account_user, foreign_key: { to_table: :account_users, on_delete: :nullify }
      t.references :created_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :identity_subject, null: false
      t.string :name, null: false
      t.text :scopes, array: true, null: false, default: []
      t.datetime :last_used_at
      t.integer :status, null: false, default: 0

      t.timestamps
    end

    add_index :mcp_integration_tokens, [:account_id, :identity_subject],
              unique: true, name: 'idx_mcp_tokens_account_subject'
  end
end
