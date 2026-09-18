# Register after Rails initialization, before any schema loader runs. The shared
# loader covers named databases and test:prepare while their target pool is active.
Rake::Task['db:load_config'].enhance do
  require_relative '../email_campaigns/reputation_schema_guards'
  ActiveRecord::Tasks::DatabaseTasks.singleton_class.prepend(EmailCampaigns::ReputationSchemaGuards::SchemaLoadHook)
end
