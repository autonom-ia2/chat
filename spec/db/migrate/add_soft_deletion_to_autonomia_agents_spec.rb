require 'rails_helper'
require Rails.root.join('db/migrate/20261006170000_add_soft_deletion_to_autonomia_agents.rb')
require Rails.root.join('db/migrate/20261027100000_add_papel_to_autonomia_agent_inboxes.rb')
store_migrations = ActiveRecord::Base.connection_pool.migration_context.migrations.select do |migration|
  %w[LinkStoreAgentInstances StoreCheckoutTargets ScheduleStoreRecovery
     CreateStoreSubscriptionCommands RequestStoreCheckoutReconciliation].include?(migration.name)
end
store_migrations.each { |migration| require Rails.root.join(migration.filename) }

RSpec.describe AddSoftDeletionToAutonomiaAgents do
  let(:store_dependencies) { store_migrations.map { |migration| migration.name.constantize.new } }

  it 'restores the database-generated schema after rollback and migration on an empty archive' do
    ActiveRecord::Base.connection.transaction(requires_new: true) do
      migration = described_class.new
      papel = AddPapelToAutonomiaAgentInboxes.new
      # Compara o schema no ponto da migration testada, sem as colunas e índices das dependências posteriores.
      # O rollback da transação restaura também essas dependências, sem recriar tabelas fora deste exemplo.
      migration.suppress_messages do
        store_dependencies.reverse_each { |store| store.suppress_messages { store.migrate(:down) } }
        papel.suppress_messages { papel.migrate(:down) }
      end

      before = StringIO.new
      ActiveRecord::SchemaDumper.dump(ActiveRecord::Base.connection_pool, before)
      migration.suppress_messages do
        migration.migrate(:down)
        migration.migrate(:up)
      end

      after = StringIO.new
      ActiveRecord::SchemaDumper.dump(ActiveRecord::Base.connection_pool, after)
      expect(after.string).to eq(before.string)
      raise ActiveRecord::Rollback
    end
  end
end
