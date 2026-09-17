class EmailCampaigns::Maintenance::HistoricalProtectionBackfill
  WORK_SECONDS = 10

  def initialize(run:, config: nil)
    @run = run
    @config = config
  end

  def call
    @token = @run.claim!
    return unless @token

    validate_actor!
    validate_apply!
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + WORK_SECONDS
    rows.each do |row|
      break unless process_row(row)
      break if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
    end
    finish_batch
  rescue ActiveRecord::RecordNotFound => e
    fail_batch(e) if EmailProtectionMaintenanceRun.exists?(@run.id)
  rescue StandardError => e
    fail_batch(e)
  end

  private

  def validate_actor!
    actor = User.find_by(id: @run.actor_id)
    return if EmailProtectionMaintenancePolicy.authorized?(actor, @run.account_id)

    raise EmailCampaigns::Maintenance::Request::Invalid, 'actor_unavailable'
  end

  def validate_apply!
    return if @run.dry_run?

    @config ||= EmailCampaigns::Maintenance::Config.new
    raise EmailCampaigns::Maintenance::Request::Invalid, 'apply_disabled' unless @config.apply_enabled?
  end

  def remaining
    if @run.phase == 'events'
      EmailCampaigns::Maintenance::Evidence.events(@run.account_id).where(email_events: { id: (@run.event_cursor + 1)..@run.event_horizon })
    else
      EmailSuppression.where(account_id: @run.account_id, id: (@run.legacy_cursor + 1)..@run.legacy_horizon)
    end
  end

  def rows
    scope = remaining.order(:id).limit(@run.batch_size)
    scope = scope.preload(recipient: :email_campaign) if @run.phase == 'events'
    scope.to_a
  end

  def process_row(row)
    # Account deletion cascades into runs (Account -> run). Registry also locks
    # Account: never hold a run while waiting for Account in the opposite order.
    Account.find(@run.account_id).with_lock do
      process_locked_row(row)
    end
  end

  def process_locked_row(row)
    @run.with_lock do
      return false unless @run.owns_lease?(@token)

      evidence = EmailCampaigns::Maintenance::Evidence.new(row, account_id: @run.account_id)
      apply_evidence(evidence)
      advance_cursor(row)
      @run.lease_expires_at = EmailProtectionMaintenanceRun::LEASE_DURATION.from_now
      @run.save!
    end
    true
  end

  def apply_evidence(evidence)
    return @run.increment_count(evidence.skip) if evidence.skip

    if @run.phase == 'events'
      @run.increment_count('eligible_events')
      protected = EmailSuppression.suppressed?(@run.account, evidence.email)
      @run.increment_count(protected ? 'already_protected_events' : 'unprotected_candidate_events')
    end
    return if @run.dry_run?

    result = EmailCampaigns::SuppressionRegistry.new(account: @run.account, email: evidence.email, campaign: evidence.campaign).block!(
      reason: evidence.reason, source: 'backfill', event_key: evidence.event_key, occurred_at: evidence.occurred_at,
      metadata: evidence.metadata.merge('maintenance_run_id' => @run.id)
    )
    count_result(result)
  end

  def count_result(result)
    key = if @run.phase == 'events'
            result.duplicate ? 'duplicate_events' : 'block_records_created'
          else
            result.duplicate ? 'duplicate_legacy_rows' : 'legacy_rows_mirrored'
          end
    @run.increment_count(key)
  end

  def advance_cursor(row)
    if @run.phase == 'events'
      @run.event_cursor = row.id
      @run.increment_count('events_processed')
    else
      @run.legacy_cursor = row.id
      @run.increment_count('legacy_rows_processed')
    end
  end

  def finish_batch
    @run.with_lock do
      return unless @run.owns_lease?(@token)

      exhausted = !remaining.exists?
      completed = exhausted && @run.phase == 'legacy'
      @run.assign_attributes(phase: exhausted ? 'legacy' : @run.phase, status: completed ? 'completed' : 'pending',
                             lease_token: nil, lease_expires_at: nil, attempts: 0, error_code: nil,
                             next_dispatch_at: Time.current, finished_at: completed ? Time.current : nil)
      @run.save!
    end
    EmailCampaigns::Maintenance::Telemetry.emit('batch_finished', @run)
  end

  def fail_batch(error)
    return unless @token

    @run.reload.with_lock do
      return unless @run.owns_lease?(@token)

      code = error_code(error)
      if code != 'batch_failed' || @run.attempts >= EmailProtectionMaintenanceRun::MAX_ATTEMPTS
        @run.fail_run!(code)
      else
        @run.update!(status: 'pending', error_code: code, error_count: @run.error_count + 1, lease_token: nil, lease_expires_at: nil,
                     next_dispatch_at: EmailProtectionMaintenanceRun::DISPATCH_INTERVAL.from_now)
      end
    end
    EmailCampaigns::Maintenance::Telemetry.emit('batch_failed', @run)
  rescue ActiveRecord::RecordNotFound
    nil
  end

  def error_code(error)
    return 'invalid_configuration' if error.is_a?(EmailCampaigns::Maintenance::Config::Invalid)
    return error.message if error.is_a?(EmailCampaigns::Maintenance::Request::Invalid) && %w[apply_disabled actor_unavailable].include?(error.message)

    'batch_failed'
  end
end
