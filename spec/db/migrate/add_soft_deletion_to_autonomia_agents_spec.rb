require 'rails_helper'
require Rails.root.join('db/migrate/20261006170000_add_soft_deletion_to_autonomia_agents.rb')

RSpec.describe AddSoftDeletionToAutonomiaAgents do
  it 'restores the database-generated schema after rollback and migration on an empty archive' do
    before = StringIO.new
    ActiveRecord::SchemaDumper.dump(ActiveRecord::Base.connection_pool, before)

    ActiveRecord::Base.connection.transaction(requires_new: true) do
      migration = described_class.new
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
