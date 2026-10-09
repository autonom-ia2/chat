module DeferInteractiveAi
  private

  def defer_interactive_ai(operation, inputs, state_agent: nil)
    inputs = inputs.deep_dup
    prepare_agent_test!(inputs, state_agent) if operation.to_s == 'agent_test'

    id = Crm::Ai::InteractiveRequest.create(
      account_user: Current.account_user, operation: operation,
      inputs: inputs, locale: I18n.locale.to_s, integration_token_id: current_integration_token&.id
    )
    Crm::Ai::InteractiveJob.perform_later(id)
    render json: { id: id, status: 'pending', poll_url: "/api/v1/accounts/#{Current.account.id}/ai_requests/#{id}" }, status: :accepted
  end

  def prepare_agent_test!(inputs, agent)
    inputs['session_id'] ||= SecureRandom.uuid
    return unless agent

    digest = ::Autonomia::Agents::TestDigest.for_agent(agent: agent)
    inputs['tested_digest'] = digest.fetch(:tested_digest)
    inputs['tested_person_digest'] = digest.fetch(:person_digest)
    inputs['tested_material_snapshot_digest'] = digest.fetch(:material_snapshot_digest)
    inputs['material_snapshot_state'] = digest.fetch(:material_snapshot_state)
    ::Autonomia::Agents::AgentStateStore.start_pending!(
      agent: agent,
      session_id: inputs.fetch('session_id'),
      actor: Current.account_user,
      actor_permission: agent_test_permission
    )
  end

  def agent_test_permission
    Current.account_user.permission_granted?('autonomia_manage') ? 'autonomia_manage' : 'autonomia_view'
  end
end
