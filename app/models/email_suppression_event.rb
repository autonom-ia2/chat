class EmailSuppressionEvent < ApplicationRecord
  belongs_to :email_suppression_state, optional: true
  belongs_to :account, optional: true

  validates :email_suppression_state_id, :account_id, :event_key, :action, :reason, :source,
            :occurred_at, :first_seen_at, :last_seen_at, presence: true
  validates :event_key, length: { maximum: 200 }
  validate :same_account

  # Append-only through the application. There is intentionally no dependent destroy.
  def readonly?
    persisted?
  end

  private

  def same_account
    errors.add(:account, 'must match suppression') if email_suppression_state && email_suppression_state.account_id != account_id
  end
end
