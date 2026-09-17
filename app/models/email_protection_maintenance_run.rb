class EmailProtectionMaintenanceRun < ApplicationRecord
  LEASE_DURATION = 2.minutes
  DISPATCH_INTERVAL = 5.minutes
  MAX_ATTEMPTS = 3
  MAX_RETRIES = 3
  COUNT_KEYS = %w[events_processed legacy_rows_processed eligible_events already_protected_events
                  block_records_created unprotected_candidate_events duplicate_events skipped_unknown_events
                  skipped_temporary_events skipped_other_events legacy_rows_mirrored duplicate_legacy_rows].freeze
  PUBLIC_FIELDS = %w[id account_id dry_run batch_size status phase event_horizon legacy_horizon event_cursor legacy_cursor
                     attempts enqueue_attempts retry_count error_count error_code started_at finished_at created_at updated_at
                     lease_expires_at next_dispatch_at].freeze

  belongs_to :account
  after_save_commit :dispatch_backfill, if: :pending_dispatch?
  after_save_commit :report_failure, if: -> { status == 'failed' && saved_change_to_status? }

  validates :reason, presence: true, length: { maximum: 200 }
  validates :idempotency_key, format: { with: /\A[a-zA-Z0-9_-]{8,100}\z/ }, uniqueness: { scope: :account_id }
  validates :dry_run, inclusion: { in: [true, false] }
  validates :batch_size, numericality: { only_integer: true, in: 1..500 }
  validates :status, inclusion: { in: %w[pending running completed failed] }
  validates :phase, inclusion: { in: %w[events legacy] }

  scope :active, -> { where(status: %w[pending running]) }
  scope :due, -> { active.where(next_dispatch_at: ..Time.current).where('lease_expires_at IS NULL OR lease_expires_at <= ?', Time.current) }

  def public_progress
    attributes.slice(*PUBLIC_FIELDS).merge('counts' => COUNT_KEYS.index_with { |key| counts.fetch(key, 0) },
                                           'elapsed_seconds' => started_at ? [(finished_at || Time.current) - started_at, 0].max.to_i : 0)
  end

  def increment_count(key)
    raise ArgumentError, 'invalid_counter' unless COUNT_KEYS.include?(key)

    self.counts = counts.merge(key => counts.fetch(key, 0) + 1)
  end

  def claim!
    with_lock do
      return unless %w[pending running].include?(status)
      return if lease_expires_at && lease_expires_at > Time.current
      next fail_run!('attempts_exhausted') if attempts >= MAX_ATTEMPTS

      update!(status: 'running', lease_token: SecureRandom.uuid, lease_expires_at: LEASE_DURATION.from_now,
              started_at: started_at || Time.current, attempts: attempts + 1, enqueue_attempts: 0)
      lease_token
    end
  end

  def owns_lease?(token)
    status == 'running' && lease_token == token && lease_expires_at && lease_expires_at > Time.current
  end

  def fail_run!(code)
    update!(status: 'failed', error_code: code, error_count: error_count + 1, finished_at: Time.current, lease_token: nil, lease_expires_at: nil)
    nil
  end

  private

  def report_failure
    EmailCampaigns::Maintenance::Telemetry.emit('run_failed', self)
  end

  def pending_dispatch?
    # Services may reload before an enclosing transaction commits. Dirty tracking
    # is then cleared, so use durable outbox state rather than saved_changes.
    status == 'pending' && next_dispatch_at <= Time.current
  end

  def dispatch_backfill
    EmailCampaigns::Maintenance::Dispatch.call(id)
  end
end
