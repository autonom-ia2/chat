require 'json'

class Autonomia::Agents::AgentStateStore
  extend Autonomia::Agents::AgentStateStoreSerialization

  # Único escritor do estado privado do Testar. O namespace mora no config existente para manter a
  # entrega sem migration, mas nunca é aceito pela porta pública de config nem serializado como blob.
  NAMESPACE = '_autonomia_agents_redesign'.freeze
  VERSION = 1
  PERMISSIONS = %w[autonomia_view autonomia_manage].freeze
  COMPLETIONS = %w[pending completed error no_response rate_limited stale].freeze
  SKIPPED_TOOL_CODES = %w[not_in_test viewer_not_allowed].freeze

  class StaleSession < StandardError; end
  class AccountMismatch < StandardError; end
  class InvalidState < StandardError; end

  class << self
    def start_pending!(agent:, session_id:, actor:, actor_permission:)
      validate_common!(agent: agent, session_id: session_id, actor: actor)
      validate_permission!(actor_permission)

      with_locked_agent(agent) do |config, namespace|
        config[NAMESPACE] = namespace.merge(
          'version' => VERSION,
          'test_invalidated_by' => nil,
          'test' => {
            'session_id' => session_id.to_s,
            'state_version' => VERSION,
            'completion' => 'pending',
            'result_real_ai_deferred' => false,
            'valid_for_state' => false,
            'writes_external' => false
          }
        )
        config
      end
    end

    def complete!(agent:, session_id:, actor:, actor_permission:, **attributes)
      validate_common!(agent: agent, session_id: session_id, actor: actor)
      permission = validate_permission!(actor_permission)
      valid_for_state = attributes[:valid_for_state]
      valid_for_state = permission == 'autonomia_manage' if valid_for_state.nil?
      safe_tools = sanitize_skipped_tools(attributes.fetch(:skipped_tools, []), agent: agent)

      complete_state(
        agent: agent, session_id: session_id,
        completion: {
          actor: actor, permission: permission, attributes: attributes,
          safe_tools: safe_tools, valid_for_state: valid_for_state
        }
      )
    end

    def fail!(agent:, session_id:, completion:)
      validate_common!(agent: agent, session_id: session_id, actor: nil)
      completion = completion.to_s
      raise InvalidState, 'invalid completion' unless COMPLETIONS.include?(completion) && completion != 'completed'

      with_locked_agent(agent) do |config, namespace|
        current_test = namespace['test'].to_h
        assert_current_session!(current_test, session_id)
        config[NAMESPACE] = namespace.merge(
          'version' => VERSION,
          'test' => {
            'session_id' => session_id.to_s,
            'state_version' => VERSION,
            'completion' => completion,
            'result_real_ai_deferred' => false,
            'valid_for_state' => false,
            'writes_external' => false
          }
        )
        config
      end
    end

    def invalidate!(agent:, reason:)
      invalidate_state!(agent: agent, reason: reason, expected_session_id: nil)
    end

    def invalidate_if_current!(agent:, reason:, session_id:)
      return false if session_id.to_s.blank?

      invalidate_state!(agent: agent, reason: reason, expected_session_id: session_id)
    end

    # A writer snapshots the pending session before changing material. The lock check keeps a
    # slower writer from erasing a newer test that started after that snapshot.
    def invalidate_state!(agent:, reason:, expected_session_id:)
      reason = reason.to_s
      raise InvalidState, 'invalid invalidation reason' unless %w[person material].include?(reason)

      invalidated = expected_session_id.nil?
      with_locked_agent(agent) do |config, namespace|
        next config if expected_session_id && namespace.dig('test', 'session_id').to_s != expected_session_id.to_s

        invalidated = true
        config[NAMESPACE] = namespace.merge(
          'version' => VERSION,
          'test' => nil,
          'test_invalidated_by' => reason
        )
        config
      end
      invalidated
    end

    # Leitura interna tipada. O controller monta o payload público a partir desta projeção; nenhuma
    # chave de config pública ou texto do resultado atravessa esta fronteira.
    def read(agent:)
      namespace = agent.config.to_h.fetch(NAMESPACE, {}).to_h
      version = namespace['version'].to_i
      {
        version: version,
        test: version == VERSION ? safe_test_projection(namespace['test']) : {},
        test_invalidated_by: namespace['test_invalidated_by']
      }
    end

    # A lista aceita apenas a forma pública fechada. Argumentos, URL, resultado e segredo nunca são
    # carregados para o namespace, mesmo que o executor os tenha recebido.
    def sanitize_skipped_tools(rows, agent: nil)
      catalog = skipped_tool_catalog(agent)
      Array(rows).map { |row| sanitize_skipped_tool(row, catalog) }
    end

    private

    def validate_common!(agent:, session_id:, actor:)
      raise InvalidState, 'session is required' if session_id.to_s.blank?
      return if actor.nil?

      actor_account_id = actor.respond_to?(:account_id) ? actor.account_id : nil
      raise AccountMismatch unless actor_account_id.to_i == agent.account_id.to_i
    end

    def validate_permission!(permission)
      permission = permission.to_s
      raise InvalidState, 'invalid actor permission' unless PERMISSIONS.include?(permission)

      permission
    end

    def assert_current_session!(test, session_id)
      raise StaleSession unless test['session_id'].to_s == session_id.to_s
    end

    def complete_state(agent:, session_id:, completion:)
      with_locked_agent(agent) do |config, namespace|
        current_test = namespace['test'].to_h
        assert_current_session!(current_test, session_id)
        raise StaleSession, 'test is no longer pending' unless current_test['completion'] == 'pending'

        config[NAMESPACE] = namespace.merge(
          'version' => VERSION,
          'test_invalidated_by' => nil,
          'test' => completed_test(session_id: session_id, completion: completion)
        )
        config
      end
    end

    def completed_test(session_id:, completion:)
      actor = completion.fetch(:actor)
      permission = completion.fetch(:permission)
      attributes = completion.fetch(:attributes)

      {
        'session_id' => session_id.to_s,
        'state_version' => VERSION,
        'completion' => 'completed',
        'result_real_ai_deferred' => attributes.fetch(:result_real_ai_deferred, true) == true,
        'valid_for_state' => completion.fetch(:valid_for_state) == true,
        'completed_by_id' => actor.id,
        'completed_by_type' => actor.class.name,
        'completed_by_permission' => permission,
        'completed_at' => Time.current.iso8601(3),
        'tested_digest' => attributes.fetch(:tested_digest).to_s,
        'tested_person_digest' => attributes[:tested_person_digest]&.to_s,
        'material_snapshot_digest' => attributes.fetch(:material_snapshot_digest).to_s,
        'material_snapshot_state' => attributes.fetch(:material_snapshot_state).to_s,
        'skipped_tools' => completion.fetch(:safe_tools),
        'writes_external' => attributes.fetch(:writes_external, false) == true
      }
    end

    def with_locked_agent(agent)
      result = nil
      agent.with_lock do
        config = agent.config.to_h.deep_dup
        namespace = config.fetch(NAMESPACE, {}).to_h.deep_dup
        namespace['version'] = VERSION
        result = yield(config, namespace)
        agent.config = result
        agent.save!
      end
      result
    end
  end
end
