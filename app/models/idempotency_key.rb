# == Schema Information
#
# Table name: idempotency_keys
#
#  id                  :bigint           not null, primary key
#  key                 :string           not null
#  request_fingerprint :string           not null
#  response_body       :jsonb
#  response_status     :integer
#  state               :integer          default("processing"), not null
#  created_at          :datetime         not null
#  account_id          :bigint           not null
#
# Indexes
#
#  idx_idempotency_keys_created_at       (created_at)
#  index_idempotency_keys_on_account_id  (account_id)
#  uniq_idempotency_keys_per_account     (account_id,key) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#

# Stripe-style idempotency record for CRM write endpoints (plan §3.3, B-API2).
# The row is CLAIMED (state: processing) inside a transaction BEFORE the action
# runs; a concurrent/retried duplicate replays the stored response once the
# original finishes (state: done). Only 2xx responses are persisted — a 5xx
# leaves the row in :processing so a later retry can re-run the action.
# TTL 24h; pruned by Crm::IdempotencyKeysCleanupJob.
class IdempotencyKey < ApplicationRecord
  TTL = 24.hours

  belongs_to :account

  # processing: claimed, action in flight or failed (no stored response yet).
  # done: a 2xx response is stored and may be replayed.
  enum state: { processing: 0, done: 1 }

  validates :key, presence: true, uniqueness: { scope: :account_id }
  validates :request_fingerprint, presence: true
end
