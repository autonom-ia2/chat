module SuperAdmin::InstagramAutomationHelper
  def instagram_automation_statuses(status)
    session = status.fetch(:session)
    session_state = {
      'active' => 'session_present', 'missing' => 'session_missing', 'invalidated' => 'operator_required',
      'invalid' => 'degraded', 'unavailable' => 'unavailable', 'unmanaged' => 'unmanaged'
    }.fetch(session.fetch(:state), 'unknown')
    proxy = status.fetch(:proxy)
    proxy_state = if proxy.fetch(:configured)
                    proxy.fetch(:valid) ? 'configured' : 'degraded'
                  else
                    'not_configured'
                  end

    {
      configuration: status.fetch(:config_complete) ? 'configured' : 'not_configured',
      session: session_state,
      manager: status.fetch(:manager_connectivity) == 'healthy' ? 'heartbeat_present' : status.fetch(:manager_connectivity),
      proxy: proxy_state,
      coordination: status.fetch(:coordination).fetch(:configured) ? 'configured' : 'not_configured',
      meta: status.fetch(:meta_creation_disabled) ? 'disabled' : status.fetch(:meta_connectivity)
    }
  end

  def instagram_automation_reconnect_available?(status)
    status[:managed_session] == true && status[:operator_required] == true && status[:control_available] == true &&
      %w[queued running].exclude?(status.dig(:control, 'state'))
  end

  def instagram_automation_time(value)
    return if value.blank?

    value.is_a?(String) ? Time.iso8601(value).in_time_zone : value
  end

  def instagram_automation_age(time)
    elapsed = [(Time.current - time).to_i, 0].max
    unit, count = if elapsed < 1.minute
                    ['seconds', elapsed]
                  elsif elapsed < 1.hour
                    ['minutes', elapsed / 1.minute]
                  else
                    ['hours', elapsed / 1.hour]
                  end
    t('super_admin.instagram_automation.age', age: t("super_admin.instagram_automation.elapsed.#{unit}", count: count))
  end
end
