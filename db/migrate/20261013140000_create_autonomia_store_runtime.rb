class CreateAutonomiaStoreRuntime < ActiveRecord::Migration[7.2]
  # Keep the four additive table declarations in one reversible migration.
  def change # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    create_table :autonomia_store_checkout_intents, id: :uuid, default: -> { 'gen_random_uuid()' } do |t|
      t.references :user, foreign_key: { on_delete: :nullify }
      t.references :account, foreign_key: { on_delete: :nullify }
      t.uuid :client_intent, null: false
      t.string :installation_id, null: false
      t.uuid :product_catalog_item_id, null: false
      t.string :buyer_subject, null: false
      t.jsonb :payload, null: false
      t.string :state, null: false, default: 'pending'
      t.uuid :checkout_session_id
      t.uuid :service_subscription_id
      t.decimal :access_version, precision: 30, scale: 0, null: false, default: 0
      t.string :error_code
      t.timestamps
      t.index [:user_id, :client_intent], unique: true, name: 'idx_store_checkout_intent'
    end

    create_table :autonomia_store_activations, id: :uuid, default: -> { 'gen_random_uuid()' } do |t|
      t.references :user, foreign_key: { on_delete: :nullify }
      t.references :account, foreign_key: { on_delete: :nullify }
      t.string :installation_id, null: false
      t.uuid :product_catalog_item_id, null: false
      t.string :buyer_subject, null: false
      t.uuid :service_subscription_id, null: false
      t.uuid :service_catalog_item_id, null: false
      t.string :feature_key, null: false
      t.string :resource_id, null: false
      t.string :metric_key, null: false
      t.uuid :operation_intent, null: false
      t.datetime :occurred_at, null: false
      t.string :state, null: false, default: 'preparing'
      t.uuid :reservation_id
      t.string :error_code
      t.boolean :reserve_attempted, null: false, default: false
      t.uuid :processing_token
      t.datetime :processing_at
      t.timestamps
      t.index [:user_id, :service_subscription_id, :account_id], unique: true, name: 'idx_store_activation_owner_resource'
      t.index [:account_id, :feature_key, :state], name: 'idx_store_activation_access'
      t.index :reservation_id
    end

    create_table :autonomia_store_entitlements do |t|
      t.references :account, foreign_key: { on_delete: :cascade }, null: false
      t.string :installation_id, null: false
      t.uuid :product_catalog_item_id, null: false
      t.uuid :service_catalog_item_id, null: false
      t.decimal :access_version, precision: 30, scale: 0, null: false, default: 0
      t.jsonb :payload, null: false
      t.timestamps
      t.index [:account_id, :installation_id, :product_catalog_item_id, :service_catalog_item_id], unique: true,
                                                                                                   name: 'idx_store_entitlement_stream'
    end

    create_table :autonomia_store_events, id: :uuid, default: -> { 'gen_random_uuid()' } do |t|
      t.string :body_sha256, null: false
      t.jsonb :payload, null: false
      t.string :state, null: false, default: 'pending'
      t.datetime :processed_at
      t.string :error_code
      t.timestamps
      t.index [:state, :created_at], name: 'idx_store_events_pending'
    end
  end
end
