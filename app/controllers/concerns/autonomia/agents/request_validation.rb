module Autonomia::Agents::RequestValidation
  private

  def validate_actuation_type
    return unless params[:agent].respond_to?(:key?) && params[:agent].key?(:actuation)

    requested = params.dig(:agent, :actuation)
    return if requested.is_a?(String) && ::Autonomia::Agents::Agent.actuations.key?(requested)

    render_unprocessable(I18n.t('autonomia.agents.errors.invalid_enum', locale: current_account.locale),
                         code: 'invalid_enum')
  end

  def validate_copilot_actuation
    return unless params[:agent].respond_to?(:key?)

    requested = params.dig(:agent, :actuation)
    return unless %w[internal both].include?(requested)
    return if @agent && @agent.actuation == requested
    return if ::Autonomia::Agents::CopilotAvailability.new(account: current_account).call.available

    render_unprocessable(I18n.t('autonomia.agents.errors.copilot_unavailable', locale: current_account.locale),
                         code: 'copilot_unavailable')
  end

  def validate_public_config_contract
    raw_agent_params = params[:agent]
    return unless raw_agent_params.respond_to?(:key?)

    config_key = raw_agent_params.key?(:config) ? :config : 'config'
    return unless raw_agent_params.key?(config_key)

    ::Autonomia::Agents::ConfigContract.validate_public!(raw_agent_params[config_key])
  rescue ::Autonomia::Agents::Errors::ContractError => e
    render_unprocessable(
      I18n.t(
        "autonomia.agents.errors.#{e.code}",
        locale: current_account.locale,
        default: 'This configuration key is not available through this endpoint.'
      ),
      code: e.code, key: e.key
    )
  end
end
