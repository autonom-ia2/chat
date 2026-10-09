class ProtectEmailReputationHistory < ActiveRecord::Migration[7.1]
  # rubocop:disable Metrics/MethodLength -- SQL function definitions are kept readable
  def up
    execute <<~SQL.squish
      CREATE FUNCTION email_reputation_audit_append_only() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        RAISE EXCEPTION 'email reputation audit is append-only';
      END;
      $$;
      CREATE TRIGGER email_reputation_audit_append_only
        BEFORE UPDATE OR DELETE ON email_reputation_audits
        FOR EACH ROW EXECUTE FUNCTION email_reputation_audit_append_only();

      CREATE FUNCTION email_reputation_snapshot_immutable() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF OLD.triggered_at IS NOT NULL AND NOT (NOT OLD.blocked AND NEW.blocked) AND
           (NEW.triggered_at IS DISTINCT FROM OLD.triggered_at OR NEW.trigger_snapshot IS DISTINCT FROM OLD.trigger_snapshot) THEN
          RAISE EXCEPTION 'email reputation trigger snapshot is immutable';
        END IF;
        RETURN NEW;
      END;
      $$;
      CREATE TRIGGER email_reputation_snapshot_immutable
        BEFORE UPDATE ON email_reputation_states
        FOR EACH ROW EXECUTE FUNCTION email_reputation_snapshot_immutable();
    SQL
  end

  # rubocop:enable Metrics/MethodLength

  def down
    execute <<~SQL.squish
      DROP TRIGGER email_reputation_snapshot_immutable ON email_reputation_states;
      DROP FUNCTION email_reputation_snapshot_immutable();
      DROP TRIGGER email_reputation_audit_append_only ON email_reputation_audits;
      DROP FUNCTION email_reputation_audit_append_only();
    SQL
  end
end
