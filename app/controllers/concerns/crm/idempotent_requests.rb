# Stripe-style idempotency for CRM write endpoints (plan §3.3, B-API2).
#
# Usage in a controller action:
#
#   def create
#     with_idempotency do
#       # ... do the write, call render(...) ...
#     end
#   end
#
# Behavior (claim-first / lock):
#   1. No Idempotency-Key header  -> run the action normally (no bookkeeping).
#   2. Header present, first time  -> CLAIM the row (INSERT ON CONFLICT DO
#      NOTHING, state: processing) BEFORE running the action. Run it. Persist
#      the captured response ONLY when 2xx (state: done). Never persist 5xx.
#   3. Header present, claim lost (row already exists):
#        - row state: done            -> REPLAY the stored response, add the
#                                         Idempotency-Replayed header.
#        - row state: processing      -> the original request is still in flight
#                                         (or failed); respond 409 so the caller
#                                         retries later.
#        - fingerprint mismatch       -> the key was reused for a different
#                                         request; respond 422.
module Crm::IdempotentRequests
  extend ActiveSupport::Concern

  IDEMPOTENCY_HEADER = 'Idempotency-Key'.freeze
  REPLAYED_HEADER = 'Idempotency-Replayed'.freeze

  private

  def with_idempotency(&action)
    key = request.headers[IDEMPOTENCY_HEADER].presence
    return action.call if key.blank?

    key = "#{idempotency_namespace}:#{key}" if idempotency_namespace.present?

    fingerprint = idempotency_fingerprint
    record = claim_idempotency_key(key, fingerprint)

    # Claim won: this is the first request for this key. Run the action and
    # persist the response if it is a success.
    return run_and_capture_idempotent_action(record, &action) if record.present?

    # Claim lost: a row already exists for [account, key]. Replay or reject.
    replay_idempotent_key(key, fingerprint)
  end

  # Controllers may isolate keys that share an account-level idempotency table.
  # Existing CRM endpoints keep their historical namespace-free contract.
  def idempotency_namespace
    nil
  end

  # Atomic claim: INSERT ... ON CONFLICT DO NOTHING via insert_all. Returns the
  # freshly created record when this request won the claim, or nil when a row
  # already existed (insert_all skips the conflicting row and returns nothing).
  def claim_idempotency_key(key, fingerprint)
    now = Time.current
    inserted = IdempotencyKey.insert_all(
      [{ account_id: Current.account.id, key: key, request_fingerprint: fingerprint, state: 0, created_at: now }],
      unique_by: :uniq_idempotency_keys_per_account,
      returning: %w[id]
    )
    row = inserted.first
    return nil if row.blank?

    IdempotencyKey.find(row['id'])
  end

  def run_and_capture_idempotent_action(record)
    yield_result = yield
    persist_idempotent_response(record) if success_status?(response.status)
    yield_result
  end

  def persist_idempotent_response(record)
    record.update!(
      state: :done,
      response_status: response.status,
      response_body: parsed_response_body
    )
  end

  def replay_idempotent_key(key, fingerprint)
    record = IdempotencyKey.find_by(account_id: Current.account.id, key: key)

    if record.blank?
      # Extremely narrow race: claimed-then-pruned between INSERT and SELECT.
      return render_idempotency_conflict
    end

    if record.request_fingerprint != fingerprint
      return render json: {
        error: { code: 'crm.idempotency.key_reuse', message: 'Idempotency-Key was already used for a different request.' }
      }, status: :unprocessable_entity
    end

    return render_idempotency_conflict if record.processing?

    replay_stored_response(record)
  end

  def replay_stored_response(record)
    response.headers[REPLAYED_HEADER] = 'true'
    render json: record.response_body, status: record.response_status
  end

  # 409: the original request holding this key has not produced a stored
  # response yet (still running, or failed with a non-2xx). The caller should
  # retry after a short delay.
  def render_idempotency_conflict
    render json: {
      error: { code: 'crm.idempotency.in_progress', message: 'A request with this Idempotency-Key is already in progress.' }
    }, status: :conflict
  end

  def idempotency_fingerprint
    raw = "#{request.request_method}:#{request.path}:#{request.raw_post}"
    Digest::SHA256.hexdigest(raw)
  end

  def success_status?(status)
    status.to_i.between?(200, 299)
  end

  def parsed_response_body
    body = response.body
    return {} if body.blank?

    JSON.parse(body)
  rescue JSON::ParserError
    {}
  end
end
