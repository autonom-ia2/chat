class CreateAutonomiaAgentTools < ActiveRecord::Migration[7.1]
  def change
    create_table :autonomia_agent_tools do |t|
      t.references :account, null: false, foreign_key: true
      t.references :autonomia_agent,
                   null: false,
                   foreign_key: { to_table: :autonomia_agents, on_delete: :cascade },
                   index: true
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.boolean :enabled, null: false, default: true
      t.string :http_method, null: false, default: 'POST'
      t.text :endpoint_url, null: false
      t.jsonb :headers_config, null: false, default: []
      t.text :request_body_template
      t.jsonb :param_schema, null: false, default: []
      t.jsonb :response_mapping, null: false, default: {}

      t.timestamps
    end

    add_index :autonomia_agent_tools, %i[autonomia_agent_id slug],
              unique: true,
              name: 'idx_autonomia_agent_tools_agent_slug'
    add_index :autonomia_agent_tools, %i[account_id enabled]
  end
end
