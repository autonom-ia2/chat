require 'rails_helper'
require Rails.root.join('db/migrate/20261006170000_add_soft_deletion_to_autonomia_agents.rb')
require Rails.root.join('db/migrate/20261027100000_add_papel_to_autonomia_agent_inboxes.rb')

RSpec.describe AddSoftDeletionToAutonomiaAgents do
  it 'restores the database-generated schema after rollback and migration on an empty archive' do
    before = StringIO.new
    ActiveRecord::SchemaDumper.dump(ActiveRecord::Base.connection_pool, before)

    ActiveRecord::Base.connection.transaction(requires_new: true) do
      migration = described_class.new
      # A 20261027100000 (#1433) troca o índice live_inbox_uniq que este down remove: desfaz ela antes e refaz no fim,
      # para o schema voltar igual. Banco vazio: sem área ativa, o down dela passa.
      papel = AddPapelToAutonomiaAgentInboxes.new
      migration.suppress_messages do
        papel.suppress_messages { papel.migrate(:down) }
        migration.migrate(:down)
        migration.migrate(:up)
        papel.suppress_messages { papel.migrate(:up) }
      end

      after = StringIO.new
      ActiveRecord::SchemaDumper.dump(ActiveRecord::Base.connection_pool, after)
      expect(after.string).to eq(before.string)
      raise ActiveRecord::Rollback
    end
  end
end
