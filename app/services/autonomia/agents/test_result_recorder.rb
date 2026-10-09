class Autonomia::Agents::TestResultRecorder
  # Fecha somente o resultado que terminou no caminho real do InteractiveJob. O cliente nunca envia
  # completion, digest ou ator: todos vêm do pedido Redis, do agente atual e do AccountUser revalidado.
  FAILURE_COMPLETIONS = {
    'failed' => 'error', 'timeout' => 'error', 'partial' => 'no_response',
    'no_response' => 'no_response', 'rate_limited' => 'rate_limited'
  }.freeze

  class StaleSession < StandardError; end
  class AccountMismatch < StandardError; end

  class << self
    def complete!(request:, agent:, actor:, actor_permission:, **completion_attributes)
      details = completion_details(completion_attributes).merge(
        result: normalize(completion_attributes.fetch(:result))
      )
      request = normalize(request)
      inputs = normalize(request[:inputs])
      assert_request_scope!(request: request, inputs: inputs, agent: agent, actor: actor)
      session_id = pending_session_id!(agent: agent, inputs: inputs)
      completion = failure_completion(request: request, output: details.fetch(:result))
      return fail_and_read!(agent: agent, session_id: session_id, completion: completion) if completion

      persist_completion(
        agent: agent, actor: actor, actor_permission: actor_permission, session_id: session_id, details: details
      )
    rescue Autonomia::Agents::AgentStateStore::StaleSession => e
      raise StaleSession, e.message
    end

    def public_payload(agent:, current_digests:, material_snapshot_state: nil, session_id: nil)
      state = Autonomia::Agents::AgentStateStore.read(agent: agent)
      test = state[:test].to_h
      return stale_payload if stale_session?(test, session_id)
      return nil if test.blank?

      outcome = public_outcome(
        state: state, test: test, current_digests: current_digests, session_id: session_id
      )

      public_result(test: test, outcome: outcome, material_snapshot_state: material_snapshot_state)
    end

    private

    def completion_details(attributes)
      {
        result: attributes.fetch(:result),
        current_digest: attributes.fetch(:current_digest),
        current_person_digest: attributes.fetch(:current_person_digest),
        material_snapshot_digest: attributes.fetch(:material_snapshot_digest),
        material_snapshot_state: attributes.fetch(:material_snapshot_state),
        tested_digest: attributes[:tested_digest],
        tested_person_digest: attributes[:tested_person_digest],
        tested_material_snapshot_digest: attributes[:tested_material_snapshot_digest],
        result_real_ai_deferred: attributes.fetch(:result_real_ai_deferred, true),
        valid_for_state: attributes[:valid_for_state]
      }
    end

    def pending_session_id!(agent:, inputs:)
      session_id = inputs[:session_id].to_s
      state = Autonomia::Agents::AgentStateStore.read(agent: agent)
      current_test = state[:test].to_h
      raise StaleSession unless session_id.present? && current_test[:session_id].to_s == session_id

      session_id
    end

    def failure_completion(request:, output:)
      FAILURE_COMPLETIONS[request[:status].to_s] || failure_for(output)
    end

    def fail_and_read!(agent:, session_id:, completion:)
      Autonomia::Agents::AgentStateStore.fail!(agent: agent, session_id: session_id, completion: completion)
      Autonomia::Agents::AgentStateStore.read(agent: agent)
    end

    def persist_completion(agent:, actor:, actor_permission:, session_id:, details:)
      output = details.fetch(:result)
      permission = effective_permission(actor, actor_permission)
      raise AccountMismatch if permission.blank?

      safe_tools = Autonomia::Agents::AgentStateStore.sanitize_skipped_tools(output[:skipped_tools], agent: agent)
      Autonomia::Agents::AgentStateStore.complete!(
        agent: agent,
        session_id: session_id,
        actor: actor,
        actor_permission: permission,
        result: output,
        tested_digest: details[:tested_digest].presence || details.fetch(:current_digest),
        tested_person_digest: details[:tested_person_digest].presence || details.fetch(:current_person_digest),
        material_snapshot_digest: details[:tested_material_snapshot_digest].presence || details.fetch(:material_snapshot_digest),
        material_snapshot_state: details.fetch(:material_snapshot_state),
        skipped_tools: safe_tools,
        writes_external: output[:writes_external] == true,
        result_real_ai_deferred: details.fetch(:result_real_ai_deferred),
        valid_for_state: details[:valid_for_state].nil? ? permission == 'autonomia_manage' : details[:valid_for_state] == true
      )
    end

    def normalize(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, item), result|
          result[key.to_sym] = normalize(item)
        end
      when Array
        value.map { |item| normalize(item) }
      else
        value.respond_to?(:to_h) && !value.nil? ? normalize(value.to_h) : value
      end
    end

    def assert_request_scope!(request:, inputs:, agent:, actor:)
      raise AccountMismatch unless request[:account_id].to_i == agent.account_id.to_i
      raise AccountMismatch unless inputs[:agent_id].to_i == agent.id.to_i
      raise AccountMismatch unless request[:account_user_id].to_i == actor.id.to_i
      raise AccountMismatch unless actor.account_id.to_i == agent.account_id.to_i
    end

    def effective_permission(actor, requested)
      requested = requested.to_s
      return requested if requested == 'autonomia_view' && actor.permission_granted?('autonomia_view')
      return 'autonomia_manage' if requested == 'autonomia_manage' && actor.permission_granted?('autonomia_manage')
      return 'autonomia_view' if actor.permission_granted?('autonomia_view')

      nil
    end

    def failure_for(result)
      return FAILURE_COMPLETIONS.fetch(result[:status].to_s) if FAILURE_COMPLETIONS.key?(result[:status].to_s)
      return 'error' if result[:error].present?
      return 'no_response' if result[:reply].blank?

      nil
    end

    def safe_tool_json(tool)
      data = normalize(tool)
      { 'slug' => data[:slug].to_s, 'name' => data[:name].to_s, 'code' => data[:code].to_s }
    end

    def stale_payload
      { 'status' => 'stale', 'valid' => false, 'invalidated_by' => 'session' }
    end

    def stale_session?(test, session_id)
      session_id.present? && test[:session_id].to_s != session_id.to_s
    end

    def public_outcome(state:, test:, current_digests:, session_id:)
      Autonomia::Agents::AgentStateResolver.test_result(
        test: test.merge(test_invalidated_by: state[:test_invalidated_by]),
        current_digest: current_digests.fetch(:aggregate),
        current_person_digest: current_digests.fetch(:person),
        current_material_digest: current_digests.fetch(:material),
        state_version: state[:version],
        session_id: session_id
      )
    end

    def public_result(test:, outcome:, material_snapshot_state:)
      {
        'status' => test[:completion].to_s,
        'valid' => outcome.fetch(:valid),
        'invalidated_by' => outcome[:invalidated_by],
        'tested_digest' => test[:tested_digest],
        'material_snapshot_digest' => test[:material_snapshot_digest],
        'material_snapshot_state' => material_snapshot_state || test[:material_snapshot_state],
        'skipped_tools' => Array(test[:skipped_tools]).map { |tool| safe_tool_json(tool) },
        'writes_external' => test.fetch(:writes_external, false) == true
      }.compact
    end
  end
end
