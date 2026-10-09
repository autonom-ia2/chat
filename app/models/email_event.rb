# == Schema Information
#
# Table name: email_events
#
#  id           :bigint           not null, primary key
#  event_type   :integer          not null
#  occurred_at  :datetime         not null
#  payload      :jsonb            not null
#  url          :string
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  recipient_id :bigint           not null
#
# Indexes
#
#  idx_email_events_occurred_at        (occurred_at)
#  idx_email_events_recipient_type     (recipient_id,event_type)
#  index_email_events_on_recipient_id  (recipient_id)
#
# Foreign Keys
#
#  fk_rails_...  (recipient_id => email_campaign_recipients.id)
#
class EmailEvent < ApplicationRecord
  belongs_to :recipient, class_name: 'EmailCampaignRecipient'

  enum event_type: {
    delivered: 0, open: 1, click: 2, bounce: 3, complaint: 4, unsubscribe: 5
  }

  validates :occurred_at, presence: true

  scope :opens, -> { where(event_type: :open) }
  scope :clicks, -> { where(event_type: :click) }

  before_validation { self.occurred_at ||= Time.current }
  before_save :invalidate_reputation_observation, if: :reputation_feedback?
  after_save_commit :schedule_reputation_evaluation, if: :reputation_feedback?

  private

  def reputation_feedback?
    [event_type, event_type_in_database, *previous_changes.fetch('event_type', [])].intersect?(%w[bounce complaint])
  end

  def invalidate_reputation_observation
    return unless recipient.email_campaign.ses?

    EmailCampaigns::Reputation::EvaluationQueue.invalidate(recipient.email_campaign.account_id)
  end

  def schedule_reputation_evaluation
    return unless recipient.email_campaign.ses?

    EmailCampaigns::Reputation::EvaluationQueue.request(recipient.email_campaign.account_id)
  end
end
