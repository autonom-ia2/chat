class CreateStoreSubscriptionCommands < ActiveRecord::Migration[7.2]
  def change
    create_table :autonomia_store_subscription_commands, id: :uuid, default: -> { 'gen_random_uuid()' } do |t|
      t.references :user, foreign_key: { on_delete: :nullify }
      t.string :buyer_subject, :installation_id, null: false
      t.uuid :product_catalog_item_id, :service_subscription_id, :client_intent, null: false
      t.string :command_action, null: false
      t.bigint :expected_version, null: false
      t.string :state, null: false, default: 'pending'
      t.jsonb :receipt
      t.string :error_code
      t.uuid :processing_token
      t.datetime :processing_at
      t.datetime :next_recovery_at, null: false, default: -> { 'CURRENT_TIMESTAMP' }
      t.timestamps
      t.index [:user_id, :client_intent], unique: true, name: 'idx_store_subscription_command_intent'
      t.index [:user_id, :installation_id, :product_catalog_item_id, :service_subscription_id],
              unique: true, where: "state = 'pending'", name: 'idx_store_subscription_pending_command'
      t.index [:installation_id, :product_catalog_item_id, :next_recovery_at], where: "state = 'pending'",
                                                                               name: 'idx_store_subscription_command_recovery'
    end
  end
end
