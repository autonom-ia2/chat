class Autonomia::Agents::Publisher
  Result = Struct.new(:agent, :agent_inbox, :agent_inboxes, keyword_init: true)

  PUBLISH_CONFIG_KEYS = %w[response_window].freeze

  def initialize(agent:, inbox: nil, inboxes: nil, config: {})
    @agent = agent
    @inboxes = inboxes.nil? ? [inbox].compact : inboxes
    @agent_inboxes = []
    @config = normalize_config(config)
  end

  def perform
    ActiveRecord::Base.transaction do
      @agent.with_lock do
        validate_before_write!
        apply_publish_attributes!
        @agent.save!
        connect_inboxes!
      end
    end

    Result.new(agent: @agent.reload, agent_inbox: @agent_inboxes.first, agent_inboxes: @agent_inboxes)
  end

  private

  def validate_before_write!
    raise_rejection('missing_instruction') if @agent.instrucao_do_sistema.blank?
    raise_rejection('missing_test') unless valid_current_test?
    validate_copilot_availability!
    validate_inbox!
  end

  def validate_copilot_availability!
    return unless @agent.actuation_internal? || @agent.actuation_both?

    availability = ::Autonomia::Agents::CopilotAvailability.new(account: @agent.account).call
    raise_rejection('copilot_unavailable') unless availability.available
  end

  def validate_inbox!
    raise_rejection('agent_internal_not_connectable') if @agent.actuation_internal? && @inboxes.present?
    raise_rejection('inbox_required') if @inboxes.blank? && !@agent.actuation_internal?
  end

  def apply_publish_attributes!
    @agent.config = @agent.config.to_h.merge(@config) unless @config.empty?
    @agent.status = :active
    @agent.enabled = true
  end

  def connect_inboxes!
    return if @inboxes.blank?

    result = ::Autonomia::Agents::Operate::InboxConnector.new(agent: @agent, inboxes: @inboxes).perform(connect: true)
    raise_rejection(result.error.to_s) unless result.success?

    @agent_inboxes = result.agent_inboxes || Array(result.agent_inbox).compact
  rescue ActiveRecord::RecordNotUnique
    raise_rejection('inbox_already_connected')
  end

  def valid_current_test?
    private_state = ::Autonomia::Agents::AgentStateStore.read(agent: @agent)
    test = private_state.fetch(:test).to_h.merge(test_invalidated_by: private_state[:test_invalidated_by])
    material = ::Autonomia::Agents::MaterialProjection.new(agent: @agent).call
    digest = ::Autonomia::Agents::TestDigest.for_agent(agent: @agent, material_projection: material)

    ::Autonomia::Agents::AgentStateResolver.test_result(
      test: test,
      current_digest: digest.fetch(:tested_digest),
      current_person_digest: digest.fetch(:person_digest),
      current_material_digest: digest.fetch(:material_snapshot_digest),
      session_id: test[:session_id],
      state_version: private_state.fetch(:version),
      instruction_present: @agent.instrucao_do_sistema.present?
    ).fetch(:valid)
  end

  def normalize_config(config)
    values = config.respond_to?(:to_h) ? config.to_h.transform_keys(&:to_s) : {}
    invalid_key = values.keys.find { |key| PUBLISH_CONFIG_KEYS.exclude?(key) }
    raise_rejection('publish_field_not_allowed', key: invalid_key) if invalid_key

    values
  end

  def raise_rejection(code, key: nil)
    raise ::Autonomia::Agents::Errors::PublishRejected.new(code: code, key: key)
  end
end
