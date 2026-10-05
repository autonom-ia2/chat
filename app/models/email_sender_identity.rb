# == Schema Information
#
# Table name: email_sender_identities
#
#  id                    :bigint           not null, primary key
#  dkim_records          :jsonb            not null
#  dmarc_record          :string
#  domain                :string           not null
#  from_email            :string
#  last_error            :string
#  provider              :string           default("ses"), not null
#  ses_configuration_set :string
#  spf_record            :string
#  status                :integer          default("pending"), not null
#  verified_at           :datetime
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  account_id            :bigint           not null
#  reply_to_inbox_id     :bigint
#
# Indexes
#
#  idx_email_sender_identities_account_domain   (account_id, lower((domain)::text)) UNIQUE
#  idx_email_sender_identities_account_status   (account_id,status)
#  index_email_sender_identities_on_account_id  (account_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class EmailSenderIdentity < ApplicationRecord
  belongs_to :account

  enum status: { pending: 0, verifying: 1, verified: 2, failed: 3 }

  DOMAIN_REGEX = /\A(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,}\z/i

  before_validation :normalize_domain

  validates :domain, presence: true, format: { with: DOMAIN_REGEX }
  validates :domain, uniqueness: { scope: :account_id, case_sensitive: false }
  validates :provider, presence: true
  validate :reply_to_inbox_must_be_account_email_inbox, if: -> { reply_to_inbox_id.present? }

  scope :verified_identities, -> { where(status: :verified) }
  scope :pending_verification, -> { where(status: %i[pending verifying]) }

  def usable?
    verified?
  end

  private

  # The domain's reply inbox (#999 review B5): an e-mail inbox of the same account.
  def reply_to_inbox_must_be_account_email_inbox
    inbox = Inbox.find_by(id: reply_to_inbox_id)
    return if inbox&.account_id == account_id && inbox.channel.is_a?(Channel::Email)

    errors.add(:reply_to_inbox_id, 'must be an email inbox of the same account')
  end

  def normalize_domain
    self.domain = domain.to_s.strip.downcase.presence
  end
end
