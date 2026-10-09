module Crm::Ai::InteractiveOperationAgentTest
  AGENT_TEST_METADATA_KEYS = %i[
    agent_id session_id tested_digest tested_person_digest tested_material_snapshot_digest
    material_snapshot_state pode_editar test_mode surface writes_external
  ].freeze

  def test_agent
    return unless @data['operation'].to_s == 'agent_test'

    agent
  end

  def record_agent_test_result!(result)
    return result unless @data['operation'].to_s == 'agent_test'

    current_digest = Autonomia::Agents::TestDigest.for_agent(agent: agent)
    actor = @account.account_users.find(@account_user.id)
    actor_permission = test_actor_permission(actor)
    complete_agent_test_result!(result, actor: actor, permission: actor_permission, digest: current_digest)
    result
  end

  def record_agent_test_failure!(completion: 'error')
    return unless @data['operation'].to_s == 'agent_test'

    Autonomia::Agents::AgentStateStore.fail!(
      agent: agent,
      session_id: @inputs[:session_id],
      completion: completion
    )
  rescue ActiveRecord::RecordNotFound, Autonomia::Agents::AgentStateStore::StaleSession,
         Autonomia::Agents::AgentStateStore::InvalidState
    nil
  end

  private

  def complete_agent_test_result!(result, actor:, permission:, digest:)
    Autonomia::Agents::TestResultRecorder.complete!(
      request: @data,
      agent: agent,
      actor: actor,
      actor_permission: permission,
      result: result,
      current_digest: digest.fetch(:tested_digest),
      current_person_digest: digest.fetch(:person_digest),
      material_snapshot_digest: digest.fetch(:material_snapshot_digest),
      material_snapshot_state: digest.fetch(:material_snapshot_state),
      tested_digest: @inputs[:tested_digest],
      tested_person_digest: @inputs[:tested_person_digest],
      tested_material_snapshot_digest: @inputs[:tested_material_snapshot_digest],
      result_real_ai_deferred: true,
      valid_for_state: permission == 'autonomia_manage'
    )
  end

  def test_actor_permission(actor)
    actor.permission_granted?('autonomia_manage') ? 'autonomia_manage' : 'autonomia_view'
  end

  def playground_result
    test = @data['operation'] == 'agent_test'
    args = @inputs.except(*AGENT_TEST_METADATA_KEYS)
    pode_editar = @account_user.permission_granted?('autonomia_manage')
    result = if test
               Autonomia::Agents::Playground.new(agent: agent, pode_editar: pode_editar, **args).run
             else
               Autonomia::Agents::Copilot.new(
                 agent: agent, pode_editar: pode_editar, test_mode: true, surface: :copilot, **args
               ).suggest
             end
    JSON.parse(ApplicationController.render(
                 template: "api/v1/accounts/autonomia/agents/playground/#{test ? 'test' : 'suggest'}",
                 assigns: { agent: agent, result: result }, formats: [:json]
               ))
  end
end
