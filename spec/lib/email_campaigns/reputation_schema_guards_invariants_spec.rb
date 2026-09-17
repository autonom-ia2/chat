require 'rails_helper'

# Deliberately no installer in setup: a schema load that omitted the guards must fail.
RSpec.describe EmailCampaigns::ReputationSchemaGuards do
  let(:connection) { ActiveRecord::Base.connection }
  let(:account) { create(:account) }
  let(:audit) { EmailReputationAudit.create!(account: account, action: 'paused', snapshot: { incident: 1 }) }
  let(:state) do
    EmailReputationState.create!(account: account, blocked: true, triggered_at: Time.current.change(usec: 0),
                                 trigger_snapshot: { incident: 1 })
  end

  ["UPDATE email_reputation_audits SET action = 'rewritten'", 'DELETE FROM email_reputation_audits'].each do |statement|
    it "rejects direct SQL #{statement.split.first} of audit evidence" do
      audit_id = audit.id
      expect do
        connection.transaction(requires_new: true) { connection.execute("#{statement} WHERE id = #{audit_id}") }
      end.to raise_error(ActiveRecord::StatementInvalid, /append-only/)
      expect(audit.reload.snapshot).to eq('incident' => 1)
    end
  end

  ["trigger_snapshot = '{}'::jsonb", 'triggered_at = NULL', "triggered_at = triggered_at + INTERVAL '1 second'"].each do |assignment|
    it "rejects changing an existing incident through #{assignment}" do
      state_id = state.id
      expect do
        connection.transaction(requires_new: true) do
          connection.execute("UPDATE email_reputation_states SET #{assignment} WHERE id = #{state_id}")
        end
      end.to raise_error(ActiveRecord::StatementInvalid, /snapshot is immutable/)
      expect(state.reload.trigger_snapshot).to eq('incident' => 1)
    end
  end

  it 'permits metrics updates and release without changing the incident, but forbids erasure during release' do
    state_id = state.id
    expect do
      connection.transaction(requires_new: true) do
        connection.execute("UPDATE email_reputation_states SET blocked = false, trigger_snapshot = '{}'::jsonb WHERE id = #{state_id}")
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /snapshot is immutable/)
    connection.execute("UPDATE email_reputation_states SET blocked = false, current_metrics = '{\"sent\": 100}'::jsonb WHERE id = #{state_id}")
    expect(state.reload).to have_attributes(blocked: false, trigger_snapshot: { 'incident' => 1 }, current_metrics: { 'sent' => 100 })
    expect do
      connection.transaction(requires_new: true) do
        connection.execute("UPDATE email_reputation_states SET trigger_snapshot = '{}'::jsonb WHERE id = #{state_id}")
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /snapshot is immutable/)
  end

  it 'allows a new incident only on the transition from released to blocked' do
    state.update!(blocked: false)
    connection.execute <<~SQL.squish
      UPDATE email_reputation_states SET blocked = true, trigger_snapshot = '{"incident": 2}'::jsonb,
        triggered_at = triggered_at + INTERVAL '1 hour' WHERE id = #{state.id}
    SQL
    expect(state.reload).to have_attributes(blocked: true, trigger_snapshot: { 'incident' => 2 })
    expect do
      connection.transaction(requires_new: true) do
        connection.execute("UPDATE email_reputation_states SET trigger_snapshot = '{}'::jsonb WHERE id = #{state.id}")
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /snapshot is immutable/)
  end

  it 'allows the first snapshot when there is no previous triggered_at' do
    initial = EmailReputationState.create!(account: account)
    connection.execute <<~SQL.squish
      UPDATE email_reputation_states SET blocked = true, triggered_at = CURRENT_TIMESTAMP,
        trigger_snapshot = '{"incident": 1}'::jsonb WHERE id = #{initial.id}
    SQL
    expect(initial.reload.trigger_snapshot).to eq('incident' => 1)
    expect(initial.triggered_at).to be_present
  end
end
