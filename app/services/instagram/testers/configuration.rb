class Instagram::Testers::Configuration
  ACCEPTANCE_URL = 'https://www.instagram.com/accounts/manage_access/'.freeze
  SESSION_KEYS = %w[cookie fb_dtsg lsd jazoest user_id user_agent extra_form].freeze
  REQUIRED_SESSION_KEYS = (SESSION_KEYS - ['extra_form']).freeze
  EXTRA_FORM_KEYS = %w[__aaid __req __hs dpr __ccg __rev __s __hsi __dyn qpl_active_flow_ids].freeze

  def self.globally_enabled?
    ENV.fetch('INSTAGRAM_TESTER_AUTOMATION_ENABLED', 'false') == 'true'
  end

  def initialize(account_id:)
    @account_id = account_id.to_s
  end

  def enabled?
    ids = ENV.fetch('INSTAGRAM_TESTER_ALLOWED_ACCOUNT_IDS', '').split(',', -1).map(&:strip)
    self.class.globally_enabled? && ids.all? { |id| Instagram::Testers::Validation.id?(id) } && ids.include?(@account_id)
  end

  def available?
    return false unless production_session_available?
    return false unless proxy_available?
    return false unless managed_admin_available?

    configured_values_available?
  end

  def configured_values_available?
    Instagram::Testers::Validation.id?(app_id) && Instagram::Testers::Validation.id?(business_id) &&
      Instagram::Testers::Validation.id?(doc_id) && app_name.present? && session.present?
  end

  def ensure_available!
    raise Instagram::Testers::Error, 'not_enabled' unless enabled?
    raise Instagram::Testers::Error, 'forbidden' if ActiveModel::Type::Boolean.new.cast(GlobalConfig.get_value('DISABLE_META_INBOX_CREATION'))
    raise Instagram::Testers::Error, 'meta_unavailable' unless available?
  end

  def public_configuration
    { enabled: enabled?, available: enabled? && available?, app_name: enabled? ? app_name.presence : nil, acceptance_url: ACCEPTANCE_URL }
  end

  def app_id
    ENV.fetch('INSTAGRAM_META_DEVELOPER_APP_ID', '')
  end

  def business_id
    ENV.fetch('INSTAGRAM_META_BUSINESS_ID', '')
  end

  def doc_id
    ENV.fetch('INSTAGRAM_TESTER_ROLES_DOC_ID', '')
  end

  # The managed browser profile is pinned to one operator identity. The value
  # is deliberately configuration-only; it is never inferred from a session
  # received from the browser.
  def admin_user_id
    ENV.fetch('INSTAGRAM_TESTER_ADMIN_USER_ID', '')
  end

  def app_name
    ENV.fetch('INSTAGRAM_TESTER_APP_NAME', '')
  end

  def session_snapshot
    return managed_session_snapshot if managed_session?

    { session: env_session, version: nil }.freeze
  rescue Instagram::Testers::Error, Redis::SecureStorage::EncryptionNotConfigured, Redis::BaseError, ConnectionPool::TimeoutError
    { session: nil, version: nil }.freeze
  end

  def session
    session_snapshot[:session]
  end

  def proxy_fingerprint
    proxy.fingerprint
  end

  def managed_session?
    ENV.fetch('INSTAGRAM_TESTER_SESSION_SOURCE', 'env') == 'managed'
  end

  def proxy
    @proxy ||= Instagram::Testers::Proxy.new
  end

  def transport_options
    return proxy.transport_options if proxy.configured? || managed_session? || !Rails.env.test?

    # Synthetic Rails tests cannot inherit an ambient proxy. Production requires
    # the explicitly configured endpoint and never enters this branch.
    { http_proxyaddr: nil, max_retries: 0 }
  end

  private

  def managed_session_snapshot
    store = Instagram::Testers::SessionStore.new(configuration: self)
    store.current_snapshot
  end

  def env_session
    value = JSON.parse(ENV.fetch('INSTAGRAM_TESTER_SESSION_JSON', ''))
    require_identity = !Rails.env.test?
    normalized = Instagram::Testers::SessionSchema.normalize(value)
    return normalized if Instagram::Testers::SessionSchema.valid?(normalized, require_identity: require_identity)

    nil
  rescue JSON::ParserError
    nil
  end

  def production_session_available?
    return false if Rails.env.production? && !managed_session?
    return false if Rails.env.production? && !Instagram::Testers::CoordinationRedis.configured?

    true
  end

  def proxy_available?
    return true unless managed_session? || proxy.configured? || !Rails.env.test?

    proxy.valid?
  end

  def managed_admin_available?
    !managed_session? || Instagram::Testers::Validation.id?(admin_user_id)
  end
end
