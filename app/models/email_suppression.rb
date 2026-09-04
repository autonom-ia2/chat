# == Schema Information
#
# Table name: email_suppressions
#
#  id         :bigint           not null, primary key
#  email      :string           not null
#  reason     :string
#  source     :string
#  created_at :datetime         not null
#  account_id :bigint           not null
#
# Indexes
#
#  idx_email_suppressions_account_email    (account_id, lower((email)::text)) UNIQUE
#  index_email_suppressions_on_account_id  (account_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class EmailSuppression < ApplicationRecord
  belongs_to :account

  REASONS = %w[hard_bounce complaint unsubscribe manual].freeze
  SOURCES = %w[ses api import manual].freeze

  before_validation :normalize_email
  before_create :set_created_at

  validates :email, presence: true, format: { with: EmailCampaign::EMAIL_REGEX }
  validates :email, uniqueness: { scope: :account_id, case_sensitive: false }

  # Returns a downcased Set of suppressed emails for an account (DeliveryJob preload).
  def self.suppressed_set_for(account)
    where(account_id: account.id).pluck(:email).map(&:downcase).to_set
  end

  def self.suppressed?(account, email)
    where(account_id: account.id).where('lower(email) = ?', email.to_s.downcase).exists?
  end

  private

  def normalize_email
    self.email = email.to_s.strip.downcase.presence
  end

  def set_created_at
    self.created_at ||= Time.current
  end
end
