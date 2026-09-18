class EmailCampaigns::ReputationSchemaGuards
  GUARDS = {
    'email_reputation_audits' => {
      name: 'email_reputation_audit_append_only',
      columns: [],
      events: 'UPDATE OR DELETE',
      body: "RAISE EXCEPTION 'email reputation audit is append-only';"
    },
    'email_reputation_states' => {
      name: 'email_reputation_snapshot_immutable',
      columns: %w[blocked triggered_at trigger_snapshot],
      events: 'UPDATE',
      body: <<~SQL.squish
        IF OLD.triggered_at IS NOT NULL AND NOT (NOT OLD.blocked AND NEW.blocked) AND
           (NEW.triggered_at IS DISTINCT FROM OLD.triggered_at OR NEW.trigger_snapshot IS DISTINCT FROM OLD.trigger_snapshot) THEN
          RAISE EXCEPTION 'email reputation trigger snapshot is immutable';
        END IF;
        RETURN NEW;
      SQL
    }
  }.freeze

  # Registered only by the Rake file: application boot must never install DDL.
  module SchemaLoadHook
    def load_schema(db_config, format = ActiveRecord.schema_format, file = nil)
      result = super
      return result unless file || schema_dump_path(db_config, format)

      # Rails still holds the target database's temporary pool here. An enhanced
      # db:schema:load task would run too late, after restoring the original pool.
      installer = EmailCampaigns::ReputationSchemaGuards.new(migration_connection)
      installer.install! if installer.applicable?
      result
    end
  end

  def initialize(connection)
    @connection = connection
  end

  def applicable?
    GUARDS.all? do |table, guard|
      @connection.table_exists?(table) && (guard[:columns] - @connection.columns(table).map(&:name)).empty?
    end
  end

  def install!
    raise ArgumentError, 'Email reputation guard tables/columns are missing' unless applicable?

    @connection.transaction do
      GUARDS.each do |table, guard|
        schema = table_schema(table)
        relation = qualified_name(schema, table)
        function = qualified_name(schema, guard[:name])
        trigger = @connection.quote_column_name(guard[:name])
        @connection.execute <<~SQL.squish
          CREATE OR REPLACE FUNCTION #{function}() RETURNS trigger LANGUAGE plpgsql AS $$
          BEGIN
            #{guard[:body]}
          END;
          $$;
          DROP TRIGGER IF EXISTS #{trigger} ON #{relation};
          CREATE TRIGGER #{trigger} BEFORE #{guard[:events]} ON #{relation}
            FOR EACH ROW EXECUTE FUNCTION #{function}();
        SQL
      end
    end
  end

  def uninstall!
    @connection.transaction do
      GUARDS.each do |table, guard|
        schema = table_schema(table)
        next unless schema

        @connection.execute <<~SQL.squish
          DROP TRIGGER IF EXISTS #{@connection.quote_column_name(guard[:name])} ON #{qualified_name(schema, table)};
          DROP FUNCTION IF EXISTS #{qualified_name(schema, guard[:name])}();
        SQL
      end
    end
  end

  private

  def table_schema(table)
    @connection.select_value(<<~SQL.squish)
      SELECT namespace.nspname FROM pg_class relation
      JOIN pg_namespace namespace ON namespace.oid = relation.relnamespace
      WHERE relation.oid = to_regclass(#{@connection.quote(table)})
    SQL
  end

  def qualified_name(schema, name)
    [schema, name].map { |part| @connection.quote_column_name(part) }.join('.')
  end
end
