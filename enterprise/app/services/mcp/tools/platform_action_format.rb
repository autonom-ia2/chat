# What a write action accepts, before platform_action (#3106).
class Mcp::Tools::PlatformActionFormat < Mcp::Tools::Base
  tool_name 'platform_action_format'
  description 'Tell what a write action accepts: where each field goes, which exist, their types, which are required ' \
              'and which values each list accepts. Check it before platform_action and build the body only from it. ' \
              'Changes nothing.'
  scope 'platform:read'
  annotations(read_only_hint: true, destructive_hint: false, open_world_hint: false)
  input_schema(
    properties: {
      action: { type: 'string', description: 'An action from platform_catalog, like "POST crm/pipelines".' },
      field: { type: 'string', description: 'Only one JSON field of the action, or a branch of it, when the summary asks for it.' }
    },
    required: ['action']
  )

  def self.perform(action:, field: nil)
    action = action.to_s.strip
    return error_response(outside_catalog(action)) unless acoes.catalogo.include?(action)

    format = Autonomia::Guide::Formatos.resumo_para_o_modelo(action, campo: field.to_s.strip.presence)
    return text_response("No format known for \"#{action}\". Send only the fields the user named, and check the answer.") if format.nil?

    note = acoes.desfazivel?(action) ? nil : 'This action cannot be undone: confirm with the user before platform_action.'
    text_response([format, note].compact.join("\n"))
  end
end
