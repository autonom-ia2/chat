class CreateAiProviderCredentials < ActiveRecord::Migration[7.2]
  def change
    create_table :ai_provider_credentials do |t|
      t.string :provider, null: false
      t.text :api_key, null: false
      t.timestamps
    end

    add_index :ai_provider_credentials, :provider, unique: true
    add_column :email_campaign_imports, :schema_resolution, :jsonb, null: false, default: {}
  end
end
