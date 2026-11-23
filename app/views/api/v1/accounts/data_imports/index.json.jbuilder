json.payload do
  json.array! @data_imports do |data_import|
    json.partial! 'api/v1/accounts/data_imports/data_import', formats: [:json], data_import: data_import
  end
end
json.can_create_import !Current.account.data_imports.active_imports.exists?
# Fork (upgrade 4.20.1, #3120): same rule as DataImportPolicy#integration_import? (integration_manage, #2027), not administrator.
user_context = { user: Current.user, account: Current.account, account_user: Current.account_user }
json.integration_imports_enabled DataImportPolicy.new(user_context, DataImport).integration_import?
