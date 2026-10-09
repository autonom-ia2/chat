module Autonomia::Agents::AgentStateStoreSerialization
  private

  def safe_test_projection(raw)
    return nil unless raw.respond_to?(:to_h)

    allowed = %w[
      session_id state_version completion result_real_ai_deferred valid_for_state
      completed_by_id completed_by_type completed_by_permission completed_at tested_digest
      tested_person_digest material_snapshot_digest material_snapshot_state skipped_tools writes_external
    ]
    projection = raw.to_h.slice(*allowed).deep_dup.deep_symbolize_keys
    projection[:writes_external] = projection[:writes_external] == true
    projection
  end

  def skipped_tool_catalog(agent)
    native = Autonomia::Agents::Tools::Registry.all.to_h { |tool| [tool.slug.to_s, tool.tool_name.to_s] }
    return native unless agent

    persisted = agent.tools.to_a.to_h { |tool| [tool.slug.to_s, tool.name.to_s] }
    specialists = agent.specialists.to_a.each_with_object({}) do |specialist, catalog|
      function_name = specialist.function_name.to_s
      next unless function_name.start_with?(Autonomia::Agents::Specialist::FUNCTION_PREFIX)

      # O Answerer só grava a identidade da função (`consultar_*`), nunca o nome vindo do modelo.
      # O vínculo do especialista com este agente é a fonte fechada que autoriza a leitura pública.
      catalog[function_name] = function_name
    end
    persisted.merge(native).merge(specialists)
  end

  def sanitize_skipped_tool(row, catalog)
    data = row.respond_to?(:to_h) ? row.to_h : {}
    slug = data[:slug] || data['slug']
    name = data[:name] || data['name']
    code = data[:code] || data['code']
    expected_name = catalog[slug.to_s]
    validate_skipped_tool!(slug: slug, name: name, code: code, expected_name: expected_name)

    { 'slug' => slug.to_s, 'name' => expected_name, 'code' => code.to_s }
  end

  def validate_skipped_tool!(slug:, name:, code:, expected_name:)
    valid_name = slug.to_s.present? && name.to_s.present? && expected_name == name.to_s
    valid_code = Autonomia::Agents::AgentStateStore::SKIPPED_TOOL_CODES.include?(code.to_s)
    return if valid_name && valid_code

    raise Autonomia::Agents::AgentStateStore::InvalidState, 'invalid skipped tool'
  end
end
