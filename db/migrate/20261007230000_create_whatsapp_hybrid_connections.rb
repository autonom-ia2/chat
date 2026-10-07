class CreateWhatsappHybridConnections < ActiveRecord::Migration[7.2]
  def change
    create_table :whatsapp_hybrid_connections do |t|
      t.bigint :account_id, null: false
      t.bigint :inbox_id, null: false
      t.string :session_name, null: false
      t.string :status, null: false, default: 'pending'
      t.string :connected_phone
      t.datetime :risk_accepted_at
      t.bigint :risk_accepted_by_id
      t.string :risk_accepted_ip
      t.boolean :routing_enabled, null: false, default: true
      t.jsonb :disabled_origins, null: false, default: []
      t.integer :rate_limit_per_minute, null: false, default: 20
      t.datetime :status_checked_at
      t.timestamps
    end

    add_index :whatsapp_hybrid_connections, :inbox_id, unique: true
    add_index :whatsapp_hybrid_connections, :session_name, unique: true
    add_index :whatsapp_hybrid_connections, :account_id
  end
end
