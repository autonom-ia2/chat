class Instagram::Testers::SessionSchema
  SESSION_KEYS = %w[cookie fb_dtsg lsd jazoest user_id user_agent extra_form].freeze
  REQUIRED_KEYS = (SESSION_KEYS - ['extra_form']).freeze
  EXTRA_FORM_KEYS = Instagram::Testers::Configuration::EXTRA_FORM_KEYS
  MAX_VALUE_BYTES = 32.kilobytes

  class << self
    def valid?(session, require_identity: true)
      value = normalize(session)
      return false unless value
      return true unless require_identity

      cookie_user_ids(value['cookie']) == [value['user_id']]
    rescue StandardError
      false
    end

    def normalize(session)
      value = normalize_hash(session)
      return unless value
      return unless (value.keys - SESSION_KEYS).empty?
      return unless REQUIRED_KEYS.all? { |key| safe_string?(value[key]) }
      return unless Instagram::Testers::Validation.id?(value['user_id'])

      extra_form = value.fetch('extra_form', {})
      return unless valid_extra_form?(extra_form)

      value['extra_form'] = normalize_hash(extra_form)
      deep_freeze(value)
    end

    private

    def normalize_hash(value)
      return unless value.is_a?(Hash)

      keys = value.keys.map(&:to_s)
      return unless keys.uniq.length == value.keys.length

      value.transform_keys(&:to_s)
    end

    def valid_extra_form?(extra_form)
      value = normalize_hash(extra_form)
      value && (value.keys - EXTRA_FORM_KEYS).empty? && value.values.all? { |item| safe_string?(item) }
    end

    def safe_string?(value)
      value.is_a?(String) && value.present? && value.bytesize <= MAX_VALUE_BYTES &&
        value.each_byte.none? { |byte| byte < 32 || byte == 127 }
    end

    def cookie_user_ids(cookie)
      cookie.split(';').filter_map do |part|
        key, value = part.strip.split('=', 2)
        value if key == 'c_user'
      end
    end

    def deep_freeze(value)
      case value
      when Hash
        value.each do |key, item|
          deep_freeze(key)
          deep_freeze(item)
        end
      when Array
        value.each { |item| deep_freeze(item) }
      end
      value.freeze
    end
  end

  private_class_method :normalize_hash, :valid_extra_form?, :safe_string?, :cookie_user_ids, :deep_freeze
end
