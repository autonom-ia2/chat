class EmailSuppressionState < ApplicationRecord
  belongs_to :account
  has_many :email_suppression_events, dependent: :restrict_with_exception

  scope :blocking, lambda {
    where(active: true).where("reason IS DISTINCT FROM 'temporary_failure' OR expires_at IS NULL OR expires_at > ?", Time.current)
  }

  validates :email, presence: true, format: { with: EmailCampaign::EMAIL_REGEX }
  validates :email, uniqueness: { scope: :account_id }
end
