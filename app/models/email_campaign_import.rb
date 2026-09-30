class EmailCampaignImport < ApplicationRecord
  belongs_to :email_campaign
  has_one_attached :source_file
  has_many :email_campaign_import_issues, dependent: :destroy

  # Capture the transition before a later reload/save clears Rails' dirty history.
  after_update :enqueue_preflight_after_commit, if: -> { saved_change_to_status? && completed? }

  enum status: { queued: 0, processing: 1, completed: 2, failed: 3 }
  scope :active, -> { where(status: [:queued, :processing]) }

  RETENTION = 1.day
  RECOVERY_AFTER = 10.minutes
  NON_RETRYABLE_ERRORS = %w[upload_failed typesafe_invalid_request].freeze

  def active?
    queued? || processing?
  end

  def retryable?
    failed? && NON_RETRYABLE_ERRORS.exclude?(error_code) && created_at > RETENTION.ago && source_file.attached?
  end

  def public_status
    { id: id, status: status, result: result, error_code: error_code, retryable: retryable? }
  end

  private

  def enqueue_preflight_after_commit
    ActiveRecord.after_all_transactions_commit { enqueue_preflight }
  end

  def enqueue_preflight
    EmailCampaigns::RecipientPreflightJob.enqueue(email_campaign_id)
  rescue StandardError => e
    # Maintenance reconciles this durable outbox from unchecked recipients.
    Rails.logger.error("[EmailCampaignImport] preflight_enqueue_error_class=#{e.class.name}")
  end
end
