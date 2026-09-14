class EmailCampaignImport < ApplicationRecord
  belongs_to :email_campaign
  has_one_attached :source_file

  enum status: { queued: 0, processing: 1, completed: 2, failed: 3 }
  scope :active, -> { where(status: [:queued, :processing]) }

  RETENTION = 1.day
  RECOVERY_AFTER = 10.minutes

  def active?
    queued? || processing?
  end

  def retryable?
    failed? && error_code != 'upload_failed' && created_at > RETENTION.ago && source_file.attached?
  end

  def public_status
    { id: id, status: status, result: result, error_code: error_code, retryable: retryable? }
  end
end
