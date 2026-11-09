# == Schema Information
#
# Table name: crm_meta_conversion_events
#
#  id                :bigint           not null, primary key
#  attribution_mode  :string
#  ctwa_clid         :string
#  currency          :string
#  dataset_id        :string
#  error_message     :text
#  event_id          :string           not null
#  event_type        :string           not null
#  funnel_stage_type :string
#  http_code         :integer
#  sent_at           :datetime
#  source            :string           default("live"), not null
#  status            :integer          default("pending"), not null
#  value_cents       :bigint
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint           not null
#  card_id           :bigint
#  pipeline_id       :bigint
#
# Indexes
#
#  idx_crm_meta_conv_account_created  (account_id,created_at)
#  idx_crm_meta_conv_card             (card_id)
#  idx_crm_meta_conv_event_id         (event_id) UNIQUE
#
class Crm::MetaConversionEvent < ApplicationRecord
  self.table_name = 'crm_meta_conversion_events'

  # Ledger append-only de eventos enviados à Meta Conversions API (CTWA revenue sync).
  # Um registro por tentativa de envio; event_id é a chave de deduplicação da Meta.
  # NUNCA guarda o token da Meta — só metadados do evento e resultado do envio.
  belongs_to :account
  belongs_to :card, class_name: 'Crm::Card', optional: true

  enum status: { pending: 0, accepted: 1, skipped: 2, error: 3 }

  # Meta may have received the event without answering, or a send stopped midway (#2738):
  # such a row is never sent again, since Meta does not dedup and the sale would count twice.
  UNKNOWN_OUTCOME = 'unknown_outcome'.freeze
  # A send takes seconds (8 s HTTP timeout); a row pending longer than this was abandoned.
  STALE_PENDING_AFTER = 10.minutes

  validates :event_id, presence: true
  validates :event_type, presence: true
  validates :status, presence: true

  scope :recentes, -> { order(created_at: :desc) }

  # Atomically claims the row of one event for one send (Crm::MetaCapi::DispatchJob), or nil.
  # The unique index on event_id is the lock for a new row: the first worker inserts it
  # `pending`; a concurrent worker hits RecordNotUnique and backs off (nil). An existing row is
  # re-read under a row lock, so two retries (or a retry and the backfill) cannot both re-claim
  # it. It short-circuits when accepted (already delivered) AND when still pending (another
  # worker owns the in-flight POST — re-claiming it would double-send, and Meta does not
  # dedup). Only error/skipped rows are re-claimed, except an unknown outcome. A pending row
  # older than STALE_PENDING_AFTER becomes that unknown outcome. The block fills the context.
  def self.claim(event_id, &)
    row = find_or_initialize_by(event_id: event_id)
    return claim_new(row, &) unless row.persisted?

    row.with_lock do
      if row.stale_pending?
        row.update!(status: :error, error_message: UNKNOWN_OUTCOME)
        next nil
      end
      next nil if row.accepted? || row.pending? || row.unknown_outcome?

      yield row
      row.update!(status: :pending)
      row
    end
  end

  def stale_pending?
    pending? && updated_at < STALE_PENDING_AFTER.ago
  end

  def unknown_outcome?
    error? && error_message == UNKNOWN_OUTCOME
  end

  def self.claim_new(row)
    yield row
    row.status = :pending
    row.save!
    row
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  # Ends a row still `pending` after an unexpected failure (#2738): a pending row is never
  # claimed again, so the event would be lost without a word. `accepted_http_code` says Meta
  # already accepted the POST (posting again would double-send: Meta does not dedup);
  # otherwise the row becomes an error with the reason, which the retry claims again (except
  # UNKNOWN_OUTCOME, never sent again).
  # Straight SQL, guarded by the status: it only touches a row nobody finished.
  def self.release_pending!(id, reason:, accepted_http_code: nil)
    now = Time.current
    attributes = if accepted_http_code
                   { status: statuses[:accepted], http_code: accepted_http_code, sent_at: now, error_message: nil }
                 else
                   { status: statuses[:error], error_message: reason }
                 end
    where(id: id, status: :pending).update_all(attributes.merge(updated_at: now)) # rubocop:disable Rails/SkipsModelValidations
  end
end
