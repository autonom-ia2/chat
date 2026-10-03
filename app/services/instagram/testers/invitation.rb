class Instagram::Testers::Invitation
  LOCK_TTL = 90
  OUTCOME_TTL = Instagram::Testers::InvitationOutcome::TTL

  def initialize(client:, app_id:, target_id:)
    @client = client
    @target_id = target_id
    @key = "instagram_testers:invite:#{app_id}:#{target_id}"
    @outcome = Instagram::Testers::InvitationOutcome.new(app_id: app_id, target_id: target_id)
  end

  def perform
    token = SecureRandom.uuid
    acquired = Instagram::Testers::CoordinationRedis.set("#{@key}:lock", token, nx: true, ex: LOCK_TTL)
    raise Instagram::Testers::Error, 'busy' unless acquired

    reconcile_and_invite
  rescue Redis::BaseError, ConnectionPool::TimeoutError
    raise Instagram::Testers::Error.new('invite_unknown'), cause: nil
  ensure
    release_lock(token) if acquired
  end

  private

  def release_lock(token)
    Instagram::Testers::CoordinationRedis.delete_if_equals("#{@key}:lock", token)
  rescue Redis::BaseError, ConnectionPool::TimeoutError
    raise Instagram::Testers::Error.new('invite_unknown'), cause: nil
  end

  def reconcile_and_invite
    status = @client.status(@target_id)
    return { status: status, invited: false } if status != 'absent'

    outcome = @outcome.state
    return { status: 'pending', invited: false } if outcome == 'pending'
    raise Instagram::Testers::Error, 'invite_unknown' if outcome.present?

    # Persist BEFORE sending: a killed request or process must not erase an ambiguous write.
    @outcome.claim!
    @client.invite(@target_id)
    @outcome.pending!
    { status: 'pending', invited: true }
  rescue Instagram::Testers::Error => e
    @outcome.rejected! if e.code == 'invite_rejected'
    raise
  end
end
