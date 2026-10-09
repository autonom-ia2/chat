class Autonomia::Agents::AgentStateResolver
  # Função pura da situação exibida na lista. Ela recebe somente fatos já carregados pelo chamador;
  # não navega associações e não toca ActiveRecord.
  class << self
    def test_result(test:, current_digest:, current_person_digest:, current_material_digest:, **context)
      test = normalize(test)
      invalidated_by = invalidation_reason(
        test: test,
        current_digest: current_digest,
        current_person_digest: current_person_digest,
        current_material_digest: current_material_digest
      )
      valid = valid_test_payload?(
        test: test,
        current_digest: current_digest,
        current_person_digest: current_person_digest,
        current_material_digest: current_material_digest,
        invalidated_by: invalidated_by,
        **context
      )
      valid = apply_instruction_presence(valid, context[:instruction_present])

      { valid: valid, invalidated_by: invalidated_by }
    end

    def resolve(agent:, thread:, test:, current_digest:, **context)
      agent = normalize(agent)
      thread = normalize(thread)
      test = normalize(test)
      context.fetch(:retention_hours)

      priority_state(agent) || resolve_draft_state(
        agent: agent, thread: thread, test: test, current_digest: current_digest, **context
      )
    end

    private

    def priority_state(agent)
      return state('archived', 'open') if agent[:archived] || agent[:deleted]
      return state('E5', 'open', text: 'Atendendo') if operating?(agent)
      return state('E6', 'open', text: 'Pausado') if paused?(agent)

      nil
    end

    def resolve_draft_state(agent:, thread:, test:, current_digest:, **context)
      retention_hours = context.fetch(:retention_hours)
      return state('E2m', 'manual', retention_hours: nil, text: 'Falta escrever as instruções') if manual_without_instruction?(agent)

      valid = valid_test?(agent: agent, test: test, current_digest: current_digest, **context)
      return state('E4', 'live', retention_hours: retention_hours, valid: true, text: 'Pronto para ligar') if valid

      invalidated_by = invalidation_reason(
        test: test,
        current_digest: current_digest,
        current_person_digest: context.fetch(:current_person_digest),
        current_material_digest: context.fetch(:current_material_digest)
      )
      return instruction_state(retention_hours: retention_hours, invalidated_by: invalidated_by) if agent[:instruction_present]

      unfinished_state(agent: agent, thread: thread, retention_hours: retention_hours)
    end

    def operating?(agent)
      agent[:status].to_s == 'active' && agent[:enabled] == true
    end

    def paused?(agent)
      agent[:status].to_s == 'paused' || (agent[:status].to_s == 'active' && agent[:enabled] == false)
    end

    def manual_without_instruction?(agent)
      agent[:mode].to_s == 'manual' && !agent[:instruction_present]
    end

    def unfinished_state(agent:, thread:, retention_hours:)
      has_response = thread[:user_response] == true || thread[:has_user_response] == true
      has_material = agent[:has_material] == true || thread[:has_material] == true || thread[:material_present] == true
      code = has_response || has_material || thread[:needs_more_info] == true ? 'E2' : 'E1'

      state(code, 'tell', retention_hours: retention_hours, text: 'Falta terminar')
    end

    def instruction_state(retention_hours:, invalidated_by:)
      state('E3', 'test', retention_hours: retention_hours, invalidated_by: invalidated_by, text: 'Falta terminar')
    end

    def apply_instruction_presence(valid, instruction_present)
      return valid if instruction_present.nil?

      valid && instruction_present == true
    end

    def valid_test?(agent:, test:, current_digest:, **context)
      test_result(
        test: test,
        current_digest: current_digest,
        current_person_digest: context.fetch(:current_person_digest),
        current_material_digest: context.fetch(:current_material_digest),
        session_id: context.fetch(:session_id),
        state_version: context.fetch(:state_version),
        instruction_present: agent[:instruction_present]
      ).fetch(:valid)
    end

    def valid_test_payload?(test:, current_digest:, current_person_digest:, current_material_digest:, **context)
      test_completed?(test) &&
        valid_test_actor?(test) &&
        valid_test_session?(test, session_id: context[:session_id], state_version: context[:state_version]) &&
        valid_test_digests?(
          test: test,
          current_digest: current_digest,
          current_person_digest: current_person_digest,
          current_material_digest: current_material_digest
        ) &&
        context[:invalidated_by].blank?
    end

    def test_completed?(test)
      test[:completion].to_s == 'completed' &&
        test[:result_real_ai_deferred] == true &&
        (!test.key?(:valid_for_state) || test[:valid_for_state] != false)
    end

    def valid_test_actor?(test)
      test[:completed_by_id].present? &&
        test[:completed_by_type].to_s == 'AccountUser' &&
        test[:completed_by_permission].to_s == 'autonomia_manage'
    end

    def valid_test_session?(test, session_id:, state_version:)
      test[:state_version].present? && state_version.present? &&
        test[:state_version].to_i == state_version.to_i &&
        test[:session_id].present? &&
        (session_id.blank? || test[:session_id].to_s == session_id.to_s)
    end

    def valid_test_digests?(test:, current_digest:, current_person_digest:, current_material_digest:)
      same_digest?(test[:tested_digest], current_digest) &&
        same_digest?(test[:tested_person_digest], current_person_digest) &&
        same_digest?(test[:material_snapshot_digest], current_material_digest)
    end

    def invalidation_reason(test:, current_digest:, current_person_digest:, current_material_digest:)
      return test[:test_invalidated_by].to_s if test[:test_invalidated_by].present?
      return unless test[:completion].to_s == 'completed'

      person_same = same_digest?(test[:tested_person_digest], current_person_digest)
      aggregate_changed = digest_changed?(test[:tested_digest], current_digest)
      material_changed = digest_changed?(test[:material_snapshot_digest], current_material_digest)
      return unless aggregate_changed || material_changed
      return 'person' unless person_same

      'material'
    end

    def digest_changed?(tested, current)
      tested.present? && current.present? && !same_digest?(tested, current)
    end

    def same_digest?(left, right)
      left.present? && right.present? && left.to_s == right.to_s
    end

    def state(code, continuation, **extra)
      { code: code, continuation: continuation }.merge(extra)
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
  end
end
