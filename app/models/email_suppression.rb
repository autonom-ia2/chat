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
  REASONS = %w[hard_bounce complaint unsubscribe manual provider_suppression].freeze
  SOURCES = %w[ses api import manual link].freeze

  before_validation :normalize_email
  before_create :set_created_at

  validates :email, presence: true, format: { with: EmailCampaign::EMAIL_REGEX }
  validates :email, uniqueness: { scope: :account_id, case_sensitive: false }

  # Every legacy row is a permanent positive, including rows written by old releases.
  def self.suppressed_set_for(account)
    legacy = where(account_id: account.id).pluck(:email)
    states = EmailSuppressionState.blocking.where(account_id: account.id).pluck(:email)
    (legacy + states).map { |email| email.strip.downcase }.to_set
  end

  def self.suppressed?(account, email)
    normalized = email.to_s.strip.downcase
    exists?(['account_id = ? AND lower(email) = ?', account.id, normalized]) ||
      EmailSuppressionState.blocking.exists?(account_id: account.id, email: normalized)
  end

  # Two bounded queries; legacy presence wins regardless of newer state's expiry.
  # Unknown legacy reason strings are exposed as a bounded permanent code.
  def self.blocking_reasons_for(account, emails)
    normalized = emails.map { |email| email.to_s.strip.downcase }.uniq
    states = EmailSuppressionState.blocking.where(account_id: account.id, email: normalized).pluck(:email, :reason).to_h
    where(account_id: account.id).where('lower(email) IN (?)', normalized).pluck(:email, :reason).each do |email, reason|
      states[email.strip.downcase] = REASONS.include?(reason) ? reason : 'legacy_suppression'
    end
    states
  end

  private

  def normalize_email
    self.email = email.to_s.strip.downcase.presence
  end

  def set_created_at
    self.created_at ||= Time.current
  end
end
