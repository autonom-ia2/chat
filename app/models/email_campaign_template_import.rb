# == Schema Information
#
# Table name: email_campaign_template_imports
#
#  id                         :bigint           not null, primary key
#  attempts                   :integer          default(0), not null
#  blocking                   :jsonb            not null
#  error_code                 :string
#  expires_at                 :datetime         not null
#  locked_until               :datetime
#  report                     :jsonb            not null
#  result_mjml                :text
#  source_kind                :string           not null
#  source_url                 :string
#  status                     :string           default("queued"), not null
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  account_id                 :bigint           not null
#  email_campaign_template_id :bigint
#  user_id                    :bigint
#
# Indexes
#
#  index_email_campaign_template_imports_on_expires_at   (expires_at)
#  index_email_template_imports_on_account_and_created   (account_id,created_at)
#  index_email_template_imports_on_template              (email_campaign_template_id)
#  index_email_template_imports_one_active_per_account   (account_id) UNIQUE WHERE status IN ('queued', 'processing')
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (email_campaign_template_id => email_campaign_templates.id) ON DELETE => nullify
#

# One "Importar modelo" request (#1099, delivery B): what came in (the `source` attachment, or the address), the state
# of the job, the report the screen reads and the MJML it produced, plus the copied images (`images`, served at
# permanent public addresses). One import is active per account (a partial unique index): its lock lasts LOCK_SECONDS
# and is renewed by the job; a worker that dies leaves it to expire, and the next claim — or the screen asking for news —
# takes it back, up to MAX_ATTEMPTS. Every write of the job is guarded by its attempt number, so a worker that lost the
# import can never overwrite the one that took it.
# The lock and the guarded writes are single conditional UPDATEs (update_all): that atomicity is the point, and the
# columns they touch have nothing to validate.
# rubocop:disable Rails/SkipsModelValidations
class EmailCampaignTemplateImport < ApplicationRecord
  STATUSES = %w[queued processing ready failed saved].freeze
  ACTIVE = %w[queued processing].freeze
  SOURCE_KINDS = EmailCampaigns::Import::Engine::SOURCE_KINDS
  LOCK_SECONDS = 120
  MAX_ATTEMPTS = 2
  EXPIRES_IN = 7.days
  MAX_URL_LENGTH = 2048

  belongs_to :account
  belongs_to :user, optional: true
  belongs_to :email_campaign_template, optional: true

  has_one_attached :source
  has_many_attached :images

  validates :status, inclusion: { in: STATUSES }
  validates :source_kind, inclusion: { in: SOURCE_KINDS }
  validates :source_url, length: { maximum: MAX_URL_LENGTH }
  validates :result_mjml, length: { maximum: EmailCampaignTemplate::BODY_MAX }
  validates :error_code, length: { maximum: 64 }

  before_validation :set_deadlines, on: :create

  scope :active, -> { where(status: ACTIVE) }
  scope :expired, -> { where(expires_at: ...Time.current).where.not(status: 'saved') }

  def active?
    ACTIVE.include?(status)
  end

  def lock_expired?(now = Time.current)
    active? && (locked_until.nil? || locked_until <= now)
  end

  # Takes the import for one worker and returns its token (the attempt number), or nil when it is finished or another
  # worker holds a lock that has not expired.
  def claim!
    now = Time.current
    taken = self.class.active.where(id: id).where('status = ? OR locked_until IS NULL OR locked_until <= ?', 'queued', now)
                .update_all(['status = ?, locked_until = ?, attempts = attempts + 1, updated_at = ?', 'processing', now + LOCK_SECONDS, now])
    return if taken.zero?

    reload.attempts
  end

  # Renews the lock between the steps of a long run.
  def extend_lock!(token)
    guarded(token, locked_until: LOCK_SECONDS.seconds.from_now)
  end

  def finish!(token, mjml:, report:, blocking: [])
    guarded(token, status: 'ready', result_mjml: mjml, report: report, blocking: blocking, error_code: nil, locked_until: nil)
  end

  def fail!(token, code, report: nil)
    changes = { status: 'failed', error_code: code.to_s, result_mjml: nil, locked_until: nil }
    changes[:report] = report if report
    guarded(token, **changes)
  end

  # Called when the screen asks for news: a lock that expired means the job died. It is queued again while attempts
  # are left, or the import fails (`stalled`) and frees the account. Returns :running, :resumed or :failed.
  def recover_if_stalled!
    return :running unless lock_expired?
    return stall! if attempts >= MAX_ATTEMPTS || created_at < (LOCK_SECONDS * (MAX_ATTEMPTS + 2)).seconds.ago

    now = Time.current
    resumed = self.class.active.where(id: id).where('locked_until IS NULL OR locked_until <= ?', now)
                  .update_all(status: 'queued', locked_until: now + LOCK_SECONDS, updated_at: now)
    return :running if resumed.zero?

    EmailCampaigns::Import::RunJob.perform_later(id)
    reload
    :resumed
  end

  # Fails an import whose job is gone, without a token: only while it is still active and its lock expired.
  def stall!
    now = Time.current
    stalled = self.class.active.where(id: id).where('locked_until IS NULL OR locked_until <= ?', now)
                  .update_all(status: 'failed', error_code: 'stalled', locked_until: nil, updated_at: now)
    reload
    stalled.zero? ? :running : :failed
  end

  private

  def set_deadlines
    self.locked_until ||= LOCK_SECONDS.seconds.from_now
    self.expires_at ||= EXPIRES_IN.from_now
  end

  def guarded(token, **changes)
    updated = self.class.where(id: id, status: 'processing', attempts: token).update_all(changes.merge(updated_at: Time.current))
    reload
    updated == 1
  end
end
# rubocop:enable Rails/SkipsModelValidations
