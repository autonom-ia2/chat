class CreateEmailCampaignImports < ActiveRecord::Migration[7.1]
  def change
    create_table :email_campaign_imports do |t|
      t.references :email_campaign, null: false, foreign_key: true
      t.integer :status, null: false, default: 0
      t.jsonb :result, null: false, default: {}
      t.string :error_code
      t.datetime :completed_at
      t.timestamps
    end
    add_index :email_campaign_imports, :email_campaign_id, unique: true,
                                                           where: 'status IN (0, 1)', name: 'idx_email_campaign_imports_active'
    add_index :email_campaign_imports, [:status, :updated_at]
  end
end
