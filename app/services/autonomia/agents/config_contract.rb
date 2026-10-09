module Autonomia::Agents::ConfigContract
  PUBLIC_KEYS = %w[
    handoff_strategy handoff_target_type handoff_target_id confidence_threshold
    audience audience_unknown_contact response_window faq_suggestions
  ].freeze

  OPERATIONAL_KEYS = %w[
    voice_reply voice_instructions humanize_delivery operate_media operate_reactions
    test_allowlist_phones silence_tokens native_tool_slugs debounce_seconds async_tools
    async_poll_intervals async_deadline_seconds
  ].freeze

  MAX_VOICE_INSTRUCTIONS = ::Autonomia::Agents::Config::MAX_QUERY_CHARS
  MAX_PHONE_ALLOWLIST = 100
  MAX_SILENCE_TOKENS = 16
  MAX_SILENCE_TOKEN_LENGTH = 200
  MAX_ASYNC_INTERVALS = 16
  MIN_DEBOUNCE_SECONDS = 2
  MAX_DEBOUNCE_SECONDS = 30
  MIN_ASYNC_INTERVAL_SECONDS = 2
  MAX_ASYNC_INTERVAL_SECONDS = 60
  MIN_ASYNC_DEADLINE_SECONDS = 30
  MAX_ASYNC_DEADLINE_SECONDS = 600
  OPERATION_VALUE_VALIDATORS = {
    'voice_reply' => ->(value) { value == true || value == false },
    'voice_instructions' => ->(value) { valid_string?(value, MAX_VOICE_INSTRUCTIONS) },
    'humanize_delivery' => ->(value) { value == true || value == false },
    'operate_media' => ->(value) { value == true || value == false },
    'operate_reactions' => ->(value) { value == true || value == false },
    'test_allowlist_phones' => ->(value) { valid_phone_array?(value) },
    'silence_tokens' => ->(value) { valid_string_array?(value, MAX_SILENCE_TOKENS, MAX_SILENCE_TOKEN_LENGTH, allow_empty: false) },
    'native_tool_slugs' => ->(value) { valid_native_tool_slugs?(value) },
    'debounce_seconds' => ->(value) { valid_number_in_range?(value, MIN_DEBOUNCE_SECONDS, MAX_DEBOUNCE_SECONDS) },
    'async_tools' => ->(value) { value == true || value == false },
    'async_poll_intervals' => ->(value) { valid_number_array?(value, MAX_ASYNC_INTERVALS, MIN_ASYNC_INTERVAL_SECONDS, MAX_ASYNC_INTERVAL_SECONDS) },
    'async_deadline_seconds' => ->(value) { valid_number_in_range?(value, MIN_ASYNC_DEADLINE_SECONDS, MAX_ASYNC_DEADLINE_SECONDS) }
  }.freeze

  module_function

  def validate_public!(raw_config)
    each_pair(raw_config).each do |pair|
      key = pair.first.to_s
      raise ::Autonomia::Agents::Errors::ConfigKeyNotAllowed, key unless PUBLIC_KEYS.include?(key)
    end
    true
  end

  def validate_operation!(raw_config, agent: nil)
    pairs = each_pair(raw_config)
    raise ::Autonomia::Agents::Errors::ConfigKeyNotAllowed, nil if pairs.empty?

    pairs.each do |key, value|
      key = key.to_s
      raise ::Autonomia::Agents::Errors::ConfigKeyNotAllowed, key unless OPERATIONAL_KEYS.include?(key)
      raise ::Autonomia::Agents::Errors::OperationValueNotAllowed, key unless valid_operation_value?(key, value, agent: agent)
    end
    true
  end

  def to_hash(raw_config)
    return {} if raw_config.nil?

    raw_config.transform_keys(&:to_s)
  end

  def each_pair(raw_config)
    raise ::Autonomia::Agents::Errors::ConfigKeyNotAllowed, nil unless raw_config.respond_to?(:each_pair)

    raw_config.each_pair.to_a
  end

  def valid_operation_value?(key, value, agent: nil)
    return false if agent&.instrucao_mantida? && key == 'native_tool_slugs'
    return true if value.nil?

    validator = OPERATION_VALUE_VALIDATORS[key]
    validator ? validator.call(value) : false
  end

  def valid_string?(value, max_length)
    value.is_a?(String) && value.valid_encoding? && value.length <= max_length
  end

  def valid_string_array?(value, max_items, max_length, allow_empty: true)
    return false unless value.is_a?(Array) && value.length <= max_items

    value.all? do |item|
      valid_string?(item, max_length) && (allow_empty || item.length.positive?)
    end
  end

  def valid_phone_array?(value)
    value.is_a?(Array) && value.length <= MAX_PHONE_ALLOWLIST && value.uniq.length == value.length &&
      value.all? { |phone| valid_e164_phone?(phone) }
  end

  def valid_e164_phone?(value)
    return false unless value.is_a?(String) && value.valid_encoding? && value.start_with?('+')

    digits = value.bytes.drop(1)
    digits.length.between?(8, 15) && digits.first.between?(49, 57) && digits.drop(1).all? do |digit|
      digit.between?(48, 57)
    end
  end

  def valid_native_tool_slugs?(value)
    return false unless value.is_a?(Array)
    return false if value.length > ::Autonomia::Agents::Tools::Registry.slugs.length

    value.uniq.length == value.length && value.all? do |slug|
      slug.is_a?(String) && ::Autonomia::Agents::Tools::Registry.slugs.include?(slug)
    end
  end

  def valid_number_array?(value, max_items, min, max)
    value.is_a?(Array) && value.length <= max_items && value.all? { |item| valid_number_in_range?(item, min, max) }
  end

  def valid_number_in_range?(value, min, max)
    value.is_a?(Numeric) && value.finite? && value >= min && value <= max
  end
end
