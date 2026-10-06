class AddSoftDeletionToAutonomiaAgents < ActiveRecord::Migration[7.2]
  def change
    add_column :autonomia_agents, :deleted_at, :datetime
    add_reference :autonomia_agents, :deleted_by, foreign_key: { to_table: :users, on_delete: :nullify }
    add_index :autonomia_agents, [:account_id, :deleted_at]

    add_column :autonomia_agent_inboxes, :deleted_at, :datetime
    remove_index :autonomia_agent_inboxes, name: 'idx_autonomia_agent_inboxes_on_inbox_uniq', column: :inbox_id, unique: true
    add_index :autonomia_agent_inboxes, :inbox_id,
              unique: true, where: 'deleted_at IS NULL', name: 'idx_autonomia_agent_inboxes_on_live_inbox_uniq'
  end
end
