# Upstream (#16181) turns data_import on in the stored feature defaults and for every account, and strips it
# from the Shopify plans and billing metadata.
# Fork (#3120, upgrade 4.20.1): kept as a no-op so the version stays in schema_migrations and no account changes. New
# accounts already get data_import from config/features.yml (enabled: true); accounts that have it off keep it off.
class EnableDataImportForAllAccounts < ActiveRecord::Migration[7.2]
  def up; end

  def down; end
end
