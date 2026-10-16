class LinkStoreAgentInstances < ActiveRecord::Migration[7.2]
  def change
    add_reference :autonomia_agents, :principal_agent, foreign_key: { to_table: :autonomia_agents }
    add_column :autonomia_agents, :store_service_catalog_item_id, :uuid
    add_column :autonomia_agents, :company_name, :string
    add_column :autonomia_agents, :supplemental_instruction, :text
    add_index :autonomia_agents, [:account_id, :principal_agent_id, :store_service_catalog_item_id],
              unique: true, where: 'principal_agent_id IS NOT NULL', name: 'idx_store_agent_instance'

    add_column :autonomia_store_activations, :target, :jsonb, null: false, default: {}
    add_reference :autonomia_store_activations, :agent, foreign_key: { to_table: :autonomia_agents, on_delete: :nullify }
    change_column_null :autonomia_store_activations, :feature_key, true
    reversible do |direction|
      direction.up do
        execute <<~SQL.squish
          UPDATE autonomia_store_activations
          SET target = jsonb_build_object('type', 'feature', 'featureKey', feature_key)
        SQL
      end
    end
  end
end
