class Instagram::Automation::Metadata
  KEYS = %w[
    INSTAGRAM_META_DEVELOPER_APP_ID
    INSTAGRAM_META_BUSINESS_ID
    INSTAGRAM_TESTER_APP_NAME
    INSTAGRAM_TESTER_ADMIN_USER_ID
    INSTAGRAM_TESTER_ROLES_DOC_ID
  ].freeze
  APP_NAME_KEY = 'INSTAGRAM_TESTER_APP_NAME'.freeze
  APP_NAME_MAX_LENGTH = 120
  ID_KEYS = (KEYS - [APP_NAME_KEY]).freeze

  class InvalidConfiguration < StandardError; end

  def values
    @values ||= read_values.freeze
  end

  def revision
    Digest::SHA256.hexdigest(values.to_json)
  end

  def read_values
    saved = InstallationConfig.where(name: KEYS).index_by(&:name)
    KEYS.index_with { |key| (saved.key?(key) ? saved.fetch(key).value : ENV.fetch(key, '')).freeze }
  end
  private :read_values

  def update!(submitted)
    validate!(submitted)
    InstallationConfig.transaction do
      submitted.sort_by { |name, _value| name }.each do |name, value|
        config = InstallationConfig.find_or_initialize_by(name: name)
        config.value = value
        config.locked = false if config.new_record?
        config.save!
      end
    end
    @values = nil
  end

  def validate!(submitted)
    valid = submitted.is_a?(Hash) && (submitted.keys - KEYS).empty? &&
            submitted.all? { |key, value| self.class.valid_value?(key, value, allow_empty: true) }
    raise InvalidConfiguration, 'invalid_configuration' unless valid
  end

  def self.valid_value?(key, value, allow_empty: false)
    return false unless value.is_a?(String)
    return true if allow_empty && value.empty?
    return valid_app_name?(value) if key == APP_NAME_KEY

    ID_KEYS.include?(key) && Instagram::Testers::Validation.id?(value)
  end

  def self.valid_app_name?(value)
    value.length.between?(1, APP_NAME_MAX_LENGTH) && !value.match?(/\A[[:space:]]|[[:space:]]\z/) && !value.match?(/[[:cntrl:]\p{Cf}]/)
  end
  private_class_method :valid_app_name?
end
