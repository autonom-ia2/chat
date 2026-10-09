class EmailCampaigns::Maintenance::Dispatch
  def self.call(id)
    run = EmailProtectionMaintenanceRun.find_by(id: id)
    return unless run

    enqueue(run) if reserve(run)
  rescue ActiveRecord::RecordNotFound
    nil # The account cascade may remove a run between lookup and lock.
  end

  def self.reserve(run)
    run.with_lock do
      next false unless %w[pending running].include?(run.status) && run.next_dispatch_at <= Time.current
      next false if run.lease_expires_at && run.lease_expires_at > Time.current
      next run.fail_run!('enqueue_exhausted') if run.enqueue_attempts >= EmailProtectionMaintenanceRun::MAX_ATTEMPTS

      run.update!(next_dispatch_at: EmailProtectionMaintenanceRun::DISPATCH_INTERVAL.from_now, enqueue_attempts: run.enqueue_attempts + 1)
      true
    end
  end

  def self.enqueue(run)
    job = EmailCampaigns::ProtectionBackfillJob.perform_later(run.id)
    raise ActiveJob::EnqueueError, 'enqueue_failed' unless job
  rescue StandardError
    run.with_lock do
      run.update!(error_count: run.error_count + 1, error_code: 'enqueue_failed') unless %w[completed failed].include?(run.status)
    end
    EmailCampaigns::Maintenance::Telemetry.emit('enqueue_failed', run)
    nil
  end
  private_class_method :reserve, :enqueue
end
