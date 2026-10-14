class ScheduleStoreRecovery < ActiveRecord::Migration[7.2]
  def change
    %i[autonomia_store_checkout_intents autonomia_store_activations autonomia_store_events].each do |table|
      add_column table, :next_recovery_at, :datetime, null: false, default: -> { 'CURRENT_TIMESTAMP' }
    end
    add_index :autonomia_store_checkout_intents, [:installation_id, :product_catalog_item_id, :next_recovery_at],
              where: "state NOT IN ('completed', 'expired', 'failed')", name: 'idx_store_checkout_recovery'
    add_index :autonomia_store_activations, [:installation_id, :product_catalog_item_id, :next_recovery_at],
              where: "state NOT IN ('disabled', 'failed')", name: 'idx_store_activation_recovery'
    add_index :autonomia_store_events, :next_recovery_at, where: "state = 'pending'", name: 'idx_store_inbox_recovery'
  end
end
