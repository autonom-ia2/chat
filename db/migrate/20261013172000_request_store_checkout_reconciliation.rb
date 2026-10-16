class RequestStoreCheckoutReconciliation < ActiveRecord::Migration[7.2]
  def change
    add_column :autonomia_store_checkout_intents, :reconciliation_requested, :boolean, null: false, default: false
    add_column :autonomia_store_checkout_intents, :reconciliation_state, :string
    add_column :autonomia_store_checkout_intents, :reconciliation_operation_id, :uuid
    remove_index :autonomia_store_checkout_intents, name: 'idx_store_checkout_recovery',
                                                    column: [:installation_id, :product_catalog_item_id, :next_recovery_at],
                                                    where: "state NOT IN ('completed', 'expired', 'failed')"
    add_index :autonomia_store_checkout_intents, [:installation_id, :product_catalog_item_id, :next_recovery_at],
              where: "state <> 'completed' AND (state NOT IN ('expired', 'failed') OR reconciliation_requested)", name: 'idx_store_checkout_recovery'
  end
end
