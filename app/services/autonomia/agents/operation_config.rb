class Autonomia::Agents::OperationConfig
  REDACTED = { 'redacted' => true }.freeze
  AUDIT_VALUE_SANITIZERS = {
    'test_allowlist_phones' => :sanitize_phones,
    'voice_instructions' => :sanitize_voice_instructions,
    'silence_tokens' => :sanitize_silence_tokens,
    'native_tool_slugs' => :sanitize_native_tool_slugs,
    'async_poll_intervals' => :sanitize_async_poll_intervals
  }.freeze

  def initialize(agent:, actor:, operation_config:, request_id: nil)
    @agent = agent
    @actor = actor
    @operation_config = operation_config
    @request_id = request_id
  end

  def perform!
    ::Autonomia::Agents::ConfigContract.validate_operation!(@operation_config, agent: @agent)

    @agent.with_lock do
      ::Autonomia::Agents::ConfigContract.validate_operation!(@operation_config, agent: @agent)
      apply_and_audit!
      @agent
    end
  end

  private

  def apply_and_audit!
    current_config = @agent.config.to_h.deep_dup
    incoming = ::Autonomia::Agents::ConfigContract.to_hash(@operation_config)
    changes = {}

    incoming.each { |key, value| record_change(current_config, changes, key, value) }

    return if changes.empty?

    @agent.update!(config: current_config)
    Audited.audit_class.create!(
      auditable: @agent,
      associated: @agent.account,
      user: @actor,
      user_type: @actor.class.name,
      action: 'update',
      request_uuid: @request_id,
      audited_changes: { 'operation_config' => changes }
    )
  end

  def record_change(current_config, changes, key, value)
    old_key_present = current_config.key?(key)
    old_value = current_config[key]
    value.nil? ? current_config.delete(key) : current_config[key] = value
    return if old_value == current_config[key] && old_key_present == current_config.key?(key)

    changes[key] = { 'old' => audit_value(key, old_value), 'new' => audit_value(key, value) }
  end

  def audit_value(key, value)
    return nil if value.nil?

    sanitizer = AUDIT_VALUE_SANITIZERS[key]
    return send(sanitizer, value) if sanitizer

    ::Autonomia::Agents::ConfigContract.valid_operation_value?(key, value, agent: @agent) ? value : REDACTED
  end

  def sanitize_phones(value)
    return REDACTED unless ::Autonomia::Agents::ConfigContract.valid_operation_value?('test_allowlist_phones', value, agent: @agent)

    value.first(::Autonomia::Agents::ConfigContract::MAX_PHONE_ALLOWLIST).map { |phone| mask_phone(phone) }
  end

  def sanitize_voice_instructions(value)
    return REDACTED unless ::Autonomia::Agents::ConfigContract.valid_operation_value?('voice_instructions', value, agent: @agent)

    { 'length' => value.length }
  end

  def sanitize_silence_tokens(value)
    return REDACTED unless ::Autonomia::Agents::ConfigContract.valid_operation_value?('silence_tokens', value, agent: @agent)

    { 'count' => value.length, 'lengths' => value.map(&:length) }
  end

  def sanitize_native_tool_slugs(value)
    return REDACTED unless ::Autonomia::Agents::ConfigContract.valid_operation_value?('native_tool_slugs', value, agent: @agent)

    { 'count' => value.length }
  end

  def sanitize_async_poll_intervals(value)
    return REDACTED unless ::Autonomia::Agents::ConfigContract.valid_operation_value?('async_poll_intervals', value, agent: @agent)

    { 'count' => value.length, 'min' => value.min, 'max' => value.max }
  end

  def mask_phone(phone)
    value = phone.to_s
    prefix = value[0, 3]
    suffix = value[-2, 2]
    bullets = '•' * [value.length - prefix.length - suffix.length, 0].max
    "#{prefix}#{bullets}#{suffix}"
  end
end
