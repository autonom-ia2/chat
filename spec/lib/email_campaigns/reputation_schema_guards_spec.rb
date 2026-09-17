require 'rails_helper'
require 'tempfile'
require Rails.root.join('db/migrate/20260916121200_protect_email_reputation_history')

RSpec.describe EmailCampaigns::ReputationSchemaGuards do
  let(:connection) { ActiveRecord::Base.connection }
  let!(:original_search_path) { connection.schema_search_path }
  let(:installer) { described_class.new(connection) }
  let(:schema_name) { "reputation_guards_#{SecureRandom.hex(6)}" }
  let(:guard_names) { %w[email_reputation_audit_append_only email_reputation_snapshot_immutable] }
  let(:guard_query) do
    <<~SQL.squish
      SELECT trigger.tgname FROM pg_trigger trigger
      JOIN pg_class relation ON relation.oid = trigger.tgrelid
      JOIN pg_namespace namespace ON namespace.oid = relation.relnamespace
      WHERE namespace.nspname = #{connection.quote(schema_name)} AND NOT trigger.tgisinternal
      ORDER BY trigger.tgname
    SQL
  end
  let(:schema_source) do
    <<~RUBY_SCHEMA
      ActiveRecord::Schema[7.1].define do
        create_table :email_reputation_audits, force: :cascade do |t|
          t.string :action
        end
        create_table :email_reputation_states, force: :cascade do |t|
          t.boolean :blocked, null: false, default: false
          t.datetime :triggered_at
          t.jsonb :trigger_snapshot, null: false, default: {}
        end
      end
    RUBY_SCHEMA
  end

  before do
    Rake::Task['db:load_config'].invoke
    connection.execute("CREATE SCHEMA #{connection.quote_column_name(schema_name)}")
    connection.schema_search_path = connection.quote_column_name(schema_name)
    connection.create_table(:email_reputation_audits) { |table| table.string :action }
    connection.create_table(:email_reputation_states) do |table|
      table.boolean :blocked, null: false, default: false
      table.datetime :triggered_at
      table.jsonb :trigger_snapshot, null: false, default: {}
    end
  end

  after do
    connection.schema_search_path = original_search_path
    connection.execute("DROP SCHEMA #{connection.quote_column_name(schema_name)} CASCADE")
  end

  it 'installs on fresh tables and is idempotent' do
    expect(connection.select_values(guard_query)).to be_empty
    installer.install!
    installer.install!
    expect(connection.select_values(guard_query)).to eq(guard_names)
  end

  it 'restores a missing trigger even when its function survived schema loading' do
    installer.install!
    connection.execute('DROP TRIGGER email_reputation_audit_append_only ON email_reputation_audits')
    installer.install!
    expect(connection.select_values(guard_query)).to eq(guard_names)
  end

  it 'restores a disabled trigger' do
    installer.install!
    connection.execute('ALTER TABLE email_reputation_audits DISABLE TRIGGER email_reputation_audit_append_only')
    installer.install!
    connection.execute("INSERT INTO email_reputation_audits (action) VALUES ('paused')")
    expect do
      connection.transaction(requires_new: true) { connection.execute('DELETE FROM email_reputation_audits') }
    end.to raise_error(ActiveRecord::StatementInvalid, /append-only/)
  end

  it 'uses the same reversible installer for the migration without dropping unrelated guards' do
    connection.execute <<~SQL.squish
      CREATE FUNCTION unrelated_guard() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RETURN NEW; END; $$;
      CREATE TRIGGER unrelated_guard BEFORE INSERT ON email_reputation_audits
        FOR EACH ROW EXECUTE FUNCTION unrelated_guard();
    SQL
    migration = ProtectEmailReputationHistory.new
    migration.up
    migration.down
    migration.down
    expect(connection.select_values(guard_query)).to eq(['unrelated_guard'])
    expect(connection.select_value("SELECT to_regprocedure('email_reputation_audit_append_only()')")).to be_nil
    expect(connection.select_value("SELECT to_regprocedure('email_reputation_snapshot_immutable()')")).to be_nil
    migration.up
    expect(connection.select_value("SELECT to_regprocedure('unrelated_guard()')")).to be_present
  end

  it 'installs functions in the table schema even when another schema is first in the search path' do
    other_schema = "#{schema_name}_first"
    connection.execute("CREATE SCHEMA #{connection.quote_column_name(other_schema)}")
    connection.schema_search_path = "#{connection.quote_column_name(other_schema)}, #{connection.quote_column_name(schema_name)}"
    installer.install!
    expect(connection.select_values(guard_query)).to eq(guard_names)
    expect(connection.select_value("SELECT to_regprocedure('#{other_schema}.email_reputation_audit_append_only()')")).to be_nil
    installer.uninstall!
    expect(connection.select_value("SELECT to_regprocedure('#{schema_name}.email_reputation_audit_append_only()')")).to be_nil
  ensure
    connection.execute("DROP SCHEMA IF EXISTS #{connection.quote_column_name(other_schema)} CASCADE")
  end

  it 'keeps identically named guards in separate schemas independent during uninstall' do
    installer.install!
    other_schema = "#{schema_name}_second"
    connection.execute("CREATE SCHEMA #{connection.quote_column_name(other_schema)}")
    %w[email_reputation_audits email_reputation_states].each do |table|
      connection.execute("CREATE TABLE #{other_schema}.#{table} (LIKE #{schema_name}.#{table} INCLUDING ALL)")
    end
    connection.schema_search_path = connection.quote_column_name(other_schema)
    installer.install!
    installer.uninstall!
    expect(connection.select_value("SELECT to_regprocedure('#{other_schema}.email_reputation_audit_append_only()')")).to be_nil
    expect(connection.select_values(guard_query)).to eq(guard_names)
    connection.schema_search_path = connection.quote_column_name(schema_name)
    connection.execute("INSERT INTO email_reputation_audits (action) VALUES ('paused')")
    expect do
      connection.transaction(requires_new: true) { connection.execute('DELETE FROM email_reputation_audits') }
    end.to raise_error(ActiveRecord::StatementInvalid, /append-only/)
  ensure
    connection.execute("DROP SCHEMA IF EXISTS #{connection.quote_column_name(other_schema)} CASCADE")
  end

  it 'installs after each actual Ruby schema load and repairs a subsequent reload' do
    Tempfile.create(['email_reputation_schema', '.rb']) do |file|
      file.write(schema_source)
      file.flush
      2.times do
        ActiveRecord::Tasks::DatabaseTasks.load_schema(connection.pool.db_config, :ruby, file.path)
        expect(connection.select_values(<<~SQL.squish)).to eq(guard_names)
          SELECT tgname FROM pg_trigger
          WHERE tgrelid IN ('email_reputation_audits'::regclass, 'email_reputation_states'::regclass)
          AND NOT tgisinternal ORDER BY tgname
        SQL
        connection.execute("INSERT INTO email_reputation_audits (action) VALUES ('paused')")
        expect do
          connection.transaction(requires_new: true) { connection.execute('DELETE FROM email_reputation_audits') }
        end.to raise_error(ActiveRecord::StatementInvalid, /append-only/)
      end
    end
  end

  it 'skips unrelated schema loads with missing tables' do
    connection.drop_table(:email_reputation_states)
    Tempfile.create(['unrelated_schema', '.rb']) do |file|
      file.write('# schema without reputation state')
      file.flush
      ActiveRecord::Tasks::DatabaseTasks.load_schema(connection.pool.db_config, :ruby, file.path)
    end
    expect(connection.select_values(guard_query)).to be_empty
    expect { installer.install! }.to raise_error(ArgumentError, %r{tables/columns are missing})
  end

  it 'skips an older schema without required columns, then installs once they exist' do
    connection.remove_column(:email_reputation_states, :trigger_snapshot)
    Tempfile.create(['older_schema', '.rb']) do |file|
      file.write('# old schema without trigger_snapshot')
      file.flush
      ActiveRecord::Tasks::DatabaseTasks.load_schema(connection.pool.db_config, :ruby, file.path)
    end
    expect(connection.select_values(guard_query)).to be_empty
    connection.add_column(:email_reputation_states, :trigger_snapshot, :jsonb, default: {}, null: false)
    installer.install!
    expect(connection.select_value("SELECT to_regprocedure('email_reputation_snapshot_immutable()')")).to be_present
  end

  it 'does not swallow installation failures after a successful schema load' do
    allow(installer).to receive(:install!).and_raise(ActiveRecord::StatementInvalid, 'guard installation failed')
    allow(described_class).to receive(:new).with(connection).and_return(installer)
    Tempfile.create(['email_reputation_schema', '.rb']) do |file|
      file.write(schema_source)
      file.flush
      expect do
        ActiveRecord::Tasks::DatabaseTasks.load_schema(connection.pool.db_config, :ruby, file.path)
      end.to raise_error(ActiveRecord::StatementInvalid, /guard installation failed/)
    end
  end
end
