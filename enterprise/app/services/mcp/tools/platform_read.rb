# Reads anything the user can see in the account, through the endpoint the screen calls (#3106).
class Mcp::Tools::PlatformRead < Mcp::Tools::Base
  MAX_CHARACTERS = 12_000

  tool_name 'platform_read'
  description 'Read real data of the account through the same endpoint the screen uses, with the user\'s permissions. ' \
              'Use it for anything the specific tools do not cover. Get the resource name from platform_catalog. ' \
              'Long lists come back trimmed with the list of fields: ask again with fields to fit more items, or with page.'
  scope 'platform:read'
  annotations(read_only_hint: true, destructive_hint: false, open_world_hint: false)
  input_schema(
    properties: {
      resource: { type: 'string', description: 'A resource from platform_catalog, like "crm/pipelines" or "contacts/:id".' },
      params: {
        type: 'object',
        description: 'Fills the ":id" parts of the resource, like {"id": "12"}. Anything else is sent as a filter, ' \
                     'the way the screen sends it, like {"pipeline_id": "10"}.'
      },
      status: { type: 'string', description: 'Filters a list by status when the resource accepts it, like "open".' },
      page: { type: 'integer', minimum: 1 },
      fields: { type: 'array', items: { type: 'string' }, description: 'Only these fields of each item, like "meta.sender.name".' }
    },
    required: ['resource']
  )

  def self.perform(resource:, params: {}, status: nil, page: nil, fields: nil)
    filters = { 'status' => status, 'page' => page&.to_s }.compact_blank
    text = consulta.ler(resource, params.to_h.deep_stringify_keys, filters, campos: Array(fields).presence, teto: MAX_CHARACTERS)

    text_response(text, error: !text.start_with?('[', '{'))
  end
end
