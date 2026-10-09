# == Schema Information
#
# Table name: email_campaign_recipients
#
#  id                :bigint           not null, primary key
#  attempts          :integer          default(0), not null
#  custom_data       :jsonb            not null
#  email             :string           not null
#  last_error        :text
#  last_event_at     :datetime
#  name              :string
#  sent_at           :datetime
#  status            :integer          default("pending"), not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  email_campaign_id :bigint           not null
#  ses_message_id    :string
#
# Indexes
#
#  idx_email_campaign_recipients_campaign_email          (email_campaign_id, lower((email)::text)) UNIQUE
#  idx_email_campaign_recipients_campaign_status         (email_campaign_id,status)
#  index_email_campaign_recipients_on_email_campaign_id  (email_campaign_id)
#  index_email_campaign_recipients_on_ses_message_id     (ses_message_id)
#
# Foreign Keys
#
#  fk_rails_...  (email_campaign_id => email_campaigns.id)
#
class EmailCampaignRecipient < ApplicationRecord
  belongs_to :email_campaign

  has_many :email_events, foreign_key: :recipient_id, dependent: :destroy, inverse_of: :recipient

  enum status: { pending: 0, sent: 1, failed: 2, suppressed: 3,
                 delivered: 4, opened: 5, clicked: 6, bounced: 7, complained: 8,
                 unsubscribed: 9 }

  MAX_ATTEMPTS = 3

  before_validation :normalize_email

  validates :email, presence: true, format: { with: EmailCampaign::EMAIL_REGEX }
  validates :email, uniqueness: { scope: :email_campaign_id, case_sensitive: false }

  def mark_sent!(ses_message_id)
    update!(status: :sent, ses_message_id: ses_message_id, sent_at: Time.current, last_error: nil)
  end

  def mark_failed!(message)
    update!(status: :failed, last_error: message.to_s.truncate(500))
  end

  def mark_suppressed!
    update!(status: :suppressed)
  end

  # Transient failure: undo the optimistic sent-claim, bump attempts, requeue as pending
  # until MAX_ATTEMPTS, then permanently failed. Uses update_columns to skip the email
  # uniqueness validator on this re-save path (no email change).
  def register_attempt!(message)
    new_attempts = attempts.to_i + 1
    next_status = new_attempts >= MAX_ATTEMPTS ? self.class.statuses[:failed] : self.class.statuses[:pending]
    update_columns(status: next_status, attempts: new_attempts,
                   last_error: message.to_s.truncate(500), updated_at: Time.current)
  end

  def retryable?
    pending? && attempts.to_i < MAX_ATTEMPTS
  end

  # Forward-only status helpers used by tracking + SNS (idempotent; never regress a
  # bounced/complained/clicked recipient back to delivered/opened).
  def mark_delivered!
    return if unsubscribed?
    return unless sent? || delivered?

    update_columns(status: self.class.statuses[:delivered], last_event_at: Time.current, updated_at: Time.current)
  end

  def mark_opened!
    return if unsubscribed? || bounced? || complained?

    update_columns(status: self.class.statuses[:opened], last_event_at: Time.current, updated_at: Time.current) unless clicked?
    touch_event_time
  end

  def mark_clicked!
    return if unsubscribed? || bounced? || complained?

    update_columns(status: self.class.statuses[:clicked], last_event_at: Time.current, updated_at: Time.current)
  end

  def mark_bounced!
    update_columns(status: self.class.statuses[:bounced], last_event_at: Time.current, updated_at: Time.current)
  end

  def mark_complained!
    update_columns(status: self.class.statuses[:complained], last_event_at: Time.current, updated_at: Time.current)
  end

  private

  def touch_event_time
    update_columns(last_event_at: Time.current, updated_at: Time.current)
  end

  def normalize_email
    self.email = email.to_s.strip.downcase.presence
  end
end
