class Instagram::Testers::InvitationOutcome
  TTL = 24.hours.to_i
  CLAIM_TOKEN = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/

  def initialize(app_id:, target_id:)
    @key = "instagram_testers:invite:#{app_id}:#{target_id}:outcome"
  end

  def state
    Instagram::Testers::CoordinationRedis.get(@key)&.partition(':')&.first
  end

  def claim!(token: nil)
    token ||= SecureRandom.uuid
    validate_claim_token!(token)
    @claim_token = token
    claim = "unknown:#{token}"
    raise Instagram::Testers::Error, 'invite_unknown' unless Instagram::Testers::CoordinationRedis.durable_set(@key, claim, ex: TTL)

    token
  end

  def pending!(token: nil)
    claim = claim_marker(token)
    return unless claim

    update_claim(claim) { |transaction| transaction.set(@key, "pending:#{claim.partition(':').last}", ex: TTL) }
  end

  def release_claim!(token: nil)
    claim = claim_marker(token)
    Instagram::Testers::CoordinationRedis.delete_if_equals(@key, claim) if claim
  end

  def reconcile
    snapshot = Instagram::Testers::CoordinationRedis.get(@key)
    status = yield
    clear_generation(snapshot) if snapshot && %w[pending accepted].include?(status)
    status
  rescue Redis::BaseError, ConnectionPool::TimeoutError
    raise Instagram::Testers::Error.new('meta_unavailable'), cause: nil
  end

  private

  def update_claim(claim, &)
    Instagram::Testers::CoordinationRedis.with do |connection|
      connection.watch(@key) do
        if connection.get(@key) != claim
          connection.unwatch
          next false
        end

        connection.multi(&)
      end
    end
  end

  def claim_marker(token)
    token ||= @claim_token
    return if token.nil?

    validate_claim_token!(token)
    "unknown:#{token}"
  end

  def validate_claim_token!(token)
    raise Instagram::Testers::Error, 'invite_unknown' unless token.is_a?(String) && CLAIM_TOKEN.match?(token)
  end

  def clear_generation(snapshot)
    generation = snapshot.partition(':').last
    return if generation.blank?

    # The same generation can only advance from unknown to pending. If that write
    # aborts the first deletion, the second comparison clears its final state.
    Instagram::Testers::CoordinationRedis.delete_if_equals(@key, "unknown:#{generation}")
    Instagram::Testers::CoordinationRedis.delete_if_equals(@key, "pending:#{generation}")
  end
end
