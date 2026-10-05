# Públicos (#992): what the spreadsheet reader found is kept on the fork tables only.
# Company links (company_id, company_result, companies_* counters) belong to #998.
class AddAudienceColumnsToCampaignImports < ActiveRecord::Migration[7.1]
  def change
    change_table :campaign_imports, bulk: true do |t|
      t.string :name
      t.jsonb :channels, null: false, default: {}
      t.jsonb :extra_columns, null: false, default: []
      t.jsonb :schema_resolution, null: false, default: {}
    end

    change_table :campaign_import_rows, bulk: true do |t|
      t.string :email_masked
      t.string :normalized_email_hash
      t.string :company_name
      t.jsonb :extra_values, null: false, default: {}
      t.index :normalized_email_hash
    end
  end
end
