class StoreCheckoutTargets < ActiveRecord::Migration[7.2]
  def change
    add_column :autonomia_store_checkout_intents, :target, :jsonb, null: false, default: {}
    reversible do |direction|
      direction.up do
        execute <<~SQL.squish
          UPDATE autonomia_store_checkout_intents
          SET target = '{"type":"feature","featureKey":"prospecting"}'::jsonb
        SQL
      end
    end
  end
end
