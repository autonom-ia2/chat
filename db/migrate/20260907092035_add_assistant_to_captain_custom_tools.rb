class AddAssistantToCaptainCustomTools < ActiveRecord::Migration[7.2]
  # Fork (upgrade 4.19.1, #3119): concurrent index changes, as docs/migrations-em-lote.md requires; same final schema.
  disable_ddl_transaction!

  def change
    add_column :captain_custom_tools, :assistant_id, :bigint
    add_index :captain_custom_tools, [:assistant_id, :slug], unique: true, algorithm: :concurrently
    remove_index :captain_custom_tools, [:account_id, :slug], unique: true, algorithm: :concurrently
  end
end
