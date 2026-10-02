class Waha::ExistingInboxUpdater
  Result = Struct.new(
    :total, :would_update, :updated, :unchanged, :skipped, :failed,
    :recovered, :recovery_failed, :halted,
    keyword_init: true
  )

  DEFAULT_HEALTH_ATTEMPTS = 30
  DEFAULT_HEALTH_INTERVAL = 1

  def initialize(client: Waha::Client.new, output: $stdout, sleeper: ->(seconds) { sleep(seconds) },
                 health_attempts: DEFAULT_HEALTH_ATTEMPTS, health_interval: DEFAULT_HEALTH_INTERVAL)
    @output = output
    @planner = Waha::ExistingInboxMigrationPlanner.new(client: client)
    @executor = Waha::ExistingInboxMigrationExecutor.new(
      client: client,
      sleeper: sleeper,
      health_attempts: health_attempts,
      health_interval: health_interval
    )
  end

  def perform(apply: false, account_id: nil, inbox_id: nil)
    result = empty_result

    scope(account_id, inbox_id).find_each do |channel|
      result.total += 1
      outcome = process_channel(channel, apply, result)
      next unless apply && %i[failed skipped].include?(outcome)

      result.halted = true
      break
    end

    result
  end

  private

  def empty_result
    Result.new(
      total: 0, would_update: 0, updated: 0, unchanged: 0, skipped: 0, failed: 0,
      recovered: 0, recovery_failed: 0, halted: false
    )
  end

  def scope(account_id, inbox_id)
    relation = Channel::Api.includes(:inbox)
                           .where("channel_api.additional_attributes ->> 'provider' = ?", 'waha')
    relation = relation.where(account_id: account_id) if account_id.present?
    relation = relation.joins(:inbox).where(inboxes: { id: inbox_id }) if inbox_id.present?
    relation
  end

  def process_channel(channel, apply, result)
    plan = @planner.build(channel)
    return unchanged(channel, result) if plan.changes.empty?

    result.would_update += 1
    return dry_run(channel, plan.changes) unless apply

    apply_plan(plan, result)
  rescue Waha::ExistingInboxMigrationPlanner::SkipError => e
    skip(channel, result, e.message)
  rescue StandardError => e
    failed_without_recovery(channel, result, e)
  end

  def apply_plan(plan, result)
    outcome = @executor.perform(plan)

    case outcome.status
    when :updated
      result.updated += 1
      log(plan.context.channel, 'UPDATED', plan.changes.join(','))
      :updated
    when :skipped
      skip(plan.context.channel, result, outcome.reason)
    when :recovered
      record_recovered_failure(plan, result, outcome)
    when :recovery_failed
      record_critical_failure(plan, result, outcome)
    else
      failed_without_recovery(plan.context.channel, result, StandardError.new(outcome.error_class))
    end
  end

  def record_recovered_failure(plan, result, outcome)
    result.failed += 1
    result.recovered += 1
    log(plan.context.channel, 'RECOVERED', outcome.error_class)
    :failed
  end

  def record_critical_failure(plan, result, outcome)
    result.failed += 1
    result.recovery_failed += 1
    log(plan.context.channel, 'CRITICAL', "#{outcome.error_class},recovery_failed")
    :failed
  end

  def skip(channel, result, detail)
    result.skipped += 1
    log(channel, 'SKIP', detail)
    :skipped
  end

  def unchanged(channel, result)
    result.unchanged += 1
    log(channel, 'OK', 'already compliant')
    :unchanged
  end

  def dry_run(channel, changes)
    log(channel, 'DRY_RUN', changes.join(','))
    :dry_run
  end

  def failed_without_recovery(channel, result, error)
    result.failed += 1
    Rails.logger.error("[Waha] existing inbox preflight failed channel=#{channel.id}: #{error.class}")
    log(channel, 'FAILED', error.class.name)
    :failed
  end

  def log(channel, status, detail)
    @output.puts(
      "[waha][existing_inbox] #{status} account=#{channel.account_id} channel=#{channel.id} " \
      "inbox=#{channel.inbox&.id || '-'} #{detail}"
    )
  end
end
