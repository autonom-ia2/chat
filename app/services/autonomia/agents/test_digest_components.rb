module Autonomia::Agents::TestDigestComponents
  private

  def material_data
    if @material_projection.respond_to?(:test_digest_input)
      input = @material_projection.test_digest_input(with_knowledge_effective: knowledge_enabled?)
      input = stringify(input)
      return {
        material_snapshot_digest: material_value(input, :material_snapshot_digest).to_s,
        material_snapshot_state: material_value(input, :material_snapshot_state).to_s,
        input: input
      }
    end

    input = stringify(@material_projection.to_h)
    input['with_knowledge_effective'] = knowledge_enabled?
    {
      material_snapshot_digest: material_value(input, :material_snapshot_digest).to_s,
      material_snapshot_state: material_value(input, :material_snapshot_state).to_s,
      input: input
    }
  end

  def knowledge_enabled?
    return !@agent.knowledge_disabled? if @agent.respond_to?(:knowledge_disabled?)

    config = @agent.respond_to?(:config) && @agent.config.is_a?(Hash) ? @agent.config : {}
    [false, 'false'].exclude?(config['with_knowledge'])
  end

  def tool_rows
    rows = @tools.map do |tool|
      {
        kind: 'http',
        id: value(tool, :id),
        slug: value(tool, :slug),
        enabled: value(tool, :enabled),
        updated_at: timestamp(value(tool, :updated_at))
      }
    end
    native_rows = if @native_tools_from_registry
                    Array(@native_tools).map do |tool|
                      { kind: 'native', slug: value(tool, :slug), name: value(tool, :tool_name, value(tool, :name)) }
                    end
                  else
                    []
                  end
    (rows + native_rows).sort_by { |row| [row[:kind].to_s, row[:id].to_i, row[:slug].to_s] }
  end

  def normalize_operation_config(config)
    normalized = config.to_h.stringify_keys.compact
    normalized['silence_tokens'] = effective_silence_tokens(normalized['silence_tokens']) if normalized.key?('silence_tokens')
    normalized
  end

  def effective_silence_tokens(raw)
    values = Array(raw).map { |token| Autonomia::Agents::Operate::Responder.normalize_silence_token(token) }.reject(&:blank?)
    values.presence || [Autonomia::Agents::Operate::Responder.normalize_silence_token(
      Autonomia::Agents::Operate::Responder::SILENCE_TOKEN
    )]
  end

  def material_value(material, key)
    return material[key.to_s] if material.respond_to?(:key?) && material.key?(key.to_s)
    return material[key.to_sym] if material.respond_to?(:key?) && material.key?(key.to_sym)

    nil
  end

  def timestamp(value)
    value.respond_to?(:iso8601) ? value.iso8601(6) : value
  end

  def stringify(value)
    case value
    when Hash
      value.each_with_object({}) do |(key, item), result|
        result[key.to_s] = stringify(item)
      end
    when Array
      value.map { |item| stringify(item) }
    else
      value.respond_to?(:to_h) && !value.nil? ? stringify(value.to_h) : value
    end
  end

  def person_values(tools_digest:, operational_config_digest:)
    values = person_core_values
    values.merge!(person_handoff_values)
    values.merge!(person_audience_values)
    values.merge!(person_runtime_values)
    values[:tools_digest] = tools_digest
    values[:operational_config_digest] = operational_config_digest
    values
  end

  def person_core_values
    {
      instruction_effective_digest: digest(value(@agent, :instrucao_do_sistema, value(@agent, :instruction))),
      name: digest(value(@agent, :name)),
      greeting: digest(value(@agent, :greeting)),
      fallback_message: digest(value(@agent, :fallback_message)),
      tone: digest(value(@agent, :tone)),
      actuation: digest(value(@agent, :actuation)),
      handoff_rule: digest(value(@agent, :handoff_rule))
    }
  end

  def person_handoff_values
    {
      handoff_strategy: digest(config_value('handoff_strategy', value(@agent, :handoff_strategy))),
      handoff_target_type: digest(config_value('handoff_target_type', value(@agent, :handoff_target_type))),
      handoff_target_id: digest(config_value('handoff_target_id', value(@agent, :handoff_target_id))),
      confidence_threshold: digest(Autonomia::Agents::Answerer.effective_confidence_threshold(@agent))
    }
  end

  def person_audience_values
    {
      audience: digest(config_value('audience', value(@agent, :audience))),
      audience_unknown_contact: digest(config_value('audience_unknown_contact', value(@agent, :audience_unknown_contact))),
      response_window: digest(config_value('response_window', value(@agent, :response_window)))
    }
  end

  def person_runtime_values
    {
      agent_type: digest(value(@agent, :agent_type)),
      mode: digest(value(@agent, :mode)),
      voice: digest(Autonomia::Agents::Config.voice_for(@agent)),
      scaffold_digest: digest(value(@agent, :scaffold)),
      guardrails_digest: digest(value(@agent, :guardrails, config_value('guardrails', nil)))
    }
  end

  def config_value(key, fallback)
    config = @agent.respond_to?(:config) && @agent.config.is_a?(Hash) ? @agent.config : {}
    return config[key.to_s] if config.key?(key.to_s)
    return config[key.to_sym] if config.key?(key.to_sym)

    fallback
  end

  def value(object, key, fallback = nil)
    return object[key] if object.respond_to?(:key?) && object.key?(key)
    return object[key.to_s] if object.respond_to?(:key?) && object.key?(key.to_s)
    return object.public_send(key) if object.respond_to?(key)

    fallback
  end
end
