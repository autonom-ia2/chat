require 'digest'
require 'json'

class Autonomia::Agents::TestDigest
  include Autonomia::Agents::TestDigestComponents
  PERSON_FIELDS = %i[
    instruction_effective_digest name greeting fallback_message tone actuation handoff_rule
    handoff_strategy handoff_target_type handoff_target_id confidence_threshold audience
    audience_unknown_contact response_window agent_type mode voice scaffold_digest guardrails_digest
    tools_digest operational_config_digest
  ].freeze

  class << self
    def for_agent(agent:, material_projection: nil, tools: nil, native_tools: nil)
      material_projection ||= Autonomia::Agents::MaterialProjection.new(agent: agent).call
      tools ||= preloaded_tools(agent)
      native_tools = effective_native_tools(agent) if native_tools.nil?
      new(
        agent: agent,
        material_projection: material_projection,
        tools: tools,
        native_tools: native_tools,
        operation_config: effective_operation_config(agent, native_tools: native_tools)
      ).call
    end

    private

    def preloaded_tools(agent)
      return [] unless agent.respond_to?(:tools)

      agent.tools.to_a
    end

    def effective_operation_config(agent, native_tools:)
      config = agent.respond_to?(:config) && agent.config.is_a?(Hash) ? agent.config : {}
      {
        'voice_reply' => Autonomia::Agents::Config.voice_reply_enabled?(agent),
        'voice_instructions' => Autonomia::Agents::Config.voice_instructions_for(agent),
        'humanize_delivery' => Autonomia::Agents::Config.humanize_delivery_enabled?(agent),
        'operate_media' => Autonomia::Agents::Config.operate_media_enabled?(agent),
        'operate_reactions' => Autonomia::Agents::Config.operate_reactions_enabled?(agent),
        'test_allowlist_phones' => config['test_allowlist_phones'] || [],
        'silence_tokens' => config['silence_tokens'] || [],
        'native_tool_slugs' => Array(native_tools).filter_map { |tool| value_from(tool, :slug) },
        'debounce_seconds' => Autonomia::Agents::Config.debounce_seconds_for(agent).to_f,
        'async_tools' => Autonomia::Agents::Tools::AsyncConfig.enabled?(agent),
        'async_poll_intervals' => Autonomia::Agents::Tools::AsyncConfig.intervals_for(agent),
        'async_deadline_seconds' => Autonomia::Agents::Tools::AsyncConfig.deadline_seconds_for(agent).to_f,
        'prompt_v2_enabled' => Autonomia::Agents::Config.prompt_v2_enabled?
      }
    end

    def effective_native_tools(agent)
      return [] unless agent.respond_to?(:ferramentas_nativas)

      Autonomia::Agents::Tools::Registry.for_agent(agent)
    end

    def value_from(object, key)
      return object[key] if object.respond_to?(:key?) && object.key?(key)
      return object[key.to_s] if object.respond_to?(:key?) && object.key?(key.to_s)
      return object.public_send(key) if object.respond_to?(key)

      nil
    end
  end

  def initialize(agent:, material_projection:, tools:, operation_config:, native_tools: nil)
    @agent = agent
    @material_projection = material_projection
    @tools = Array(tools)
    @native_tools = native_tools
    @native_tools_from_registry = !native_tools.nil?
    @operation_config = normalize_operation_config(operation_config)
  end

  def call
    material = material_data
    person_components = digest_person_components
    person_digest = digest(person_components.slice(*PERSON_FIELDS))
    aggregate = aggregate_digest(person_digest: person_digest, material_digest: material[:material_snapshot_digest])

    digest_payload(material: material, person_components: person_components,
                   person_digest: person_digest, aggregate: aggregate)
  end

  private

  def digest_person_components
    person_values(
      tools_digest: digest(tool_rows), operational_config_digest: digest(@operation_config)
    )
  end

  def aggregate_digest(person_digest:, material_digest:)
    digest(
      person_digest: person_digest,
      material_snapshot_digest: material_digest,
      with_knowledge_effective: knowledge_enabled?
    )
  end

  def digest_payload(material:, person_components:, person_digest:, aggregate:)
    material_input = material[:input]
    {
      tested_digest: aggregate,
      person_digest: person_digest,
      material_snapshot_digest: material[:material_snapshot_digest],
      material_snapshot_state: material[:material_snapshot_state],
      components: person_components.merge(
        person_digest: person_digest,
        material_snapshot_digest: material[:material_snapshot_digest],
        with_knowledge_effective: material_value(material_input, :with_knowledge_effective)
      )
    }
  end

  def digest(value)
    "sha256:#{Digest::SHA256.hexdigest(canonical_json(value))}"
  end

  def canonical_json(value)
    JSON.generate(canonicalize(value))
  end

  def canonicalize(value)
    case value
    when Hash
      value.keys.sort_by(&:to_s).to_h { |key| [key.to_s, canonicalize(value[key])] }
    when Array
      value.map { |item| canonicalize(item) }
    when Time, DateTime
      value.iso8601
    else
      value
    end
  end
end
