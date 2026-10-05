# Companies from audience imports (#998, PRD §8.1): per-row result and the final counters,
# on the fork tables only. The "Criar e ligar" switch lives in campaign_imports.options
# ('create_companies', on when absent), so it needs no column.
class AddCompanyColumnsToCampaignImports < ActiveRecord::Migration[7.1]
  def change
    change_table :campaign_imports, bulk: true do |t|
      t.integer :companies_created_count, null: false, default: 0
      t.integer :companies_reused_count, null: false, default: 0
      t.integer :companies_kept_count, null: false, default: 0
      t.integer :company_contacts_linked_count, null: false, default: 0
    end

    change_table :campaign_import_rows, bulk: true do |t|
      t.bigint :company_id
      t.string :company_result
      t.index :company_id
    end
  end
end
