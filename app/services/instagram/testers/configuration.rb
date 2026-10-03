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

  def app_name
    ENV.fetch('INSTAGRAM_TESTER_APP_NAME', '')
  end

  def session
    return @session if defined?(@session)

    value = JSON.parse(ENV.fetch('INSTAGRAM_TESTER_SESSION_JSON', ''))
    @session = valid_session?(value) ? value : nil
  rescue JSON::ParserError
    @session = nil
  end

  private

  def valid_session?(value)
    return false unless value.is_a?(Hash) && (value.keys - SESSION_KEYS).empty?
    return false unless REQUIRED_SESSION_KEYS.all? { |key| safe_string?(value[key]) }
    return false unless Instagram::Testers::Validation.id?(value['user_id'])

    valid_extra_form?(value.fetch('extra_form', {}))
  end

  def valid_extra_form?(extra)
    extra.is_a?(Hash) && (extra.keys - EXTRA_FORM_KEYS).empty? && extra.values.all? { |item| safe_string?(item) }
  end

  def safe_string?(value)
    value.is_a?(String) && value.present? && value.bytesize <= 32_768 && value.exclude?("\r") && value.exclude?("\n")
  end
end
