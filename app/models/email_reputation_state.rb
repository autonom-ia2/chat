class EmailReputationState < ApplicationRecord
  belongs_to :account
  validates :level, inclusion: { in: %w[unknown healthy warning attention high_risk paused] }
  validate :retain_trigger_snapshot

  def override_active?(now = Time.current)
    override.present? && override['revoked_at'].nil? && Time.iso8601(override.fetch('expires_at')) > now &&
      override.fetch('remaining').positive?
  end

  # First creation must acquire Account before occupying the unique state key/FK.
  # Existing-state callers only lock/update state; compound writers enter account-first.
  def self.for_account(account_id)
    state = find_by(account_id: account_id)
    return state if state

    Account.find(account_id).with_lock { create_or_find_by!(account_id: account_id) }
  end

  private

  def retain_trigger_snapshot
    return if triggered_at_in_database.nil? || (!blocked_in_database && blocked)
    return unless will_save_change_to_triggered_at? || will_save_change_to_trigger_snapshot?

    errors.add(:trigger_snapshot, 'is immutable')
  end
end
