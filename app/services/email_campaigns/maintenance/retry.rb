class EmailCampaigns::Maintenance::Retry
  def self.call(run:, actor:, config: EmailCampaigns::Maintenance::Config.new)
    run.with_lock do
      raise Pundit::NotAuthorizedError unless EmailProtectionMaintenancePolicy.authorized?(actor, run.account_id)
      raise EmailCampaigns::Maintenance::Request::Invalid, 'apply_disabled' unless run.dry_run? || config.apply_enabled?

      raise EmailCampaigns::Maintenance::Request::Invalid, 'run_not_failed' unless run.status == 'failed'
      raise EmailCampaigns::Maintenance::Request::Invalid, 'actor_mismatch' unless run.actor_id == actor.id

      raise EmailCampaigns::Maintenance::Request::Invalid, 'retries_exhausted' if run.retry_count >= EmailProtectionMaintenanceRun::MAX_RETRIES

      run.update!(retry_count: run.retry_count + 1, status: 'pending', attempts: 0, enqueue_attempts: 0, error_code: nil, finished_at: nil,
                  next_dispatch_at: Time.current, lease_token: nil, lease_expires_at: nil)
    end
    run.reload
  end
end
