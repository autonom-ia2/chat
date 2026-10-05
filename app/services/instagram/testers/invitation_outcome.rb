class Instagram::Testers::InvitationOutcome
  TTL = 24.hours.to_i

  def initialize(app_id:, target_id:)
    @key = "instagram_testers:invite:#{app_id}:#{target_id}:outcome"
  end

  def state
    Instagram::Testers::CoordinationRedis.get(@key)&.partition(':')&.first
  end

  def claim!
    @claim = "unknown:#{SecureRandom.uuid}"
    raise Instagram::Testers::Error, 'invite_unknown' unless Instagram::Testers::CoordinationRedis.durable_set(@key, @claim, ex: TTL)
  end

  def pending!
    update_claim { |transaction| transaction.set(@key, "pending:#{@claim.partition(':').last}", ex: TTL) }
  end

  def release_claim!
    Instagram::Testers::CoordinationRedis.delete_if_equals(@key, @claim) if @claim
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

  def update_claim(&)
    Instagram::Testers::CoordinationRedis.with do |connection|
      connection.watch(@key) do
        next connection.unwatch unless connection.get(@key) == @claim

        connection.multi(&)
      end
    end
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
