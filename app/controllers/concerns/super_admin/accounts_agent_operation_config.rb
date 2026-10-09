module SuperAdmin::AccountsAgentOperationConfig
  def update_agent_operation_config
    render_agent_operation_config(apply_agent_operation_config)
  rescue Autonomia::Agents::Errors::ContractError => e
    render_agent_operation_config_error(e)
  end

  private

  # ParamsWrapper is enabled globally for JSON requests. This endpoint has a
  # closed body contract, so leave its parsed body untouched while preserving
  # the wrapper for every other Accounts action.
  def _wrapper_enabled?
    return false if action_name == 'update_agent_operation_config'

    super
  end

  def operation_config_agent
    Autonomia::Agents::Agent.kept
                            .where(account_id: requested_resource.id)
                            .where("config->>'system_key' IS NULL")
                            .find(params[:agent_id])
  end

  def apply_agent_operation_config
    agent = operation_config_agent
    validate_operation_config_request!(agent)
    Autonomia::Agents::OperationConfig.new(
      agent: agent,
      actor: current_super_admin,
      operation_config: operation_config_params,
      request_id: request.request_id
    ).perform!
  end

  def render_agent_operation_config(agent)
    keys = Autonomia::Agents::ConfigContract::OPERATIONAL_KEYS
    keys -= ['native_tool_slugs'] if agent.instrucao_mantida?
    render json: {
      id: agent.id,
      operation_config: agent.config.to_h.slice(*keys)
    }, status: :ok
  end

  def render_agent_operation_config_error(error)
    render json: {
      error: I18n.t(
        "autonomia.agents.errors.#{error.code}",
        locale: requested_resource.locale,
        default: 'The requested agent setting is not valid.'
      ),
      code: error.code,
      key: error.key
    }.compact, status: :unprocessable_entity
  end

  def operation_config_params
    operation_config = ActionController::Parameters.new(request.request_parameters).require(:operation_config)
    array_keys = %w[test_allowlist_phones silence_tokens native_tool_slugs async_poll_intervals]
    scalar_keys = Autonomia::Agents::ConfigContract::OPERATIONAL_KEYS - array_keys

    permitted = operation_config.permit(
      *scalar_keys,
      test_allowlist_phones: [],
      silence_tokens: [],
      native_tool_slugs: [],
      async_poll_intervals: []
    )
    array_keys.each { |key| permitted[key] = nil if operation_config.key?(key) && operation_config[key].nil? }
    permitted
  end

  def validate_operation_config_request!(agent)
    body_parameters = request.request_parameters
    extra_body_key = body_parameters.keys.map(&:to_s).find { |key| key != 'operation_config' }
    raise Autonomia::Agents::Errors::ConfigKeyNotAllowed, extra_body_key if extra_body_key

    raw_operation_config = body_parameters['operation_config'] || body_parameters[:operation_config]
    Autonomia::Agents::ConfigContract.validate_operation!(raw_operation_config, agent: agent)
  end
end
