class Instagram::Automation::LocalStatus
  def initialize(metadata: Instagram::Automation::Metadata.new.values)
    @metadata = metadata
  end

  def call
    managed = ENV.fetch('INSTAGRAM_TESTER_SESSION_SOURCE', 'env') == 'managed'
    proxy = Instagram::Testers::Proxy.new
    {
      checked_at: Time.current,
      global_gate: Instagram::Testers::Configuration.globally_enabled?,
      config_complete: Instagram::Automation::Metadata::KEYS.all? do |key|
        Instagram::Automation::Metadata.valid_value?(key, @metadata.fetch(key))
      end,
      managed_session: managed,
      session: managed ? Instagram::Automation::SessionStatus.new.call : { state: 'unmanaged', present: nil, ttl: nil },
      proxy: { configured: proxy.configured?, valid: valid_proxy?(proxy) },
      coordination: { configured: Instagram::Testers::CoordinationRedis.configured? },
      meta_creation_disabled: ActiveModel::Type::Boolean.new.cast(InstallationConfig.find_by(name: 'DISABLE_META_INBOX_CREATION')&.value) == true,
      meta_connectivity: 'unknown',
      operator_browser_configured: managed && Instagram::Automation::OperatorBrowserTicket.configured?
    }.merge(operator_status(managed))
  end

  private

  def operator_status(managed)
    return Instagram::Automation::OperatorControl.new.status if managed

    { manager: nil, control: nil, manager_connectivity: 'unknown', operator_required: false, control_available: false }
  end

  def valid_proxy?(proxy)
    proxy.valid?
  rescue IPAddr::AddressFamilyError
    false
  end
end
