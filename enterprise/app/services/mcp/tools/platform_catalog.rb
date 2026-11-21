# What the platform can read and do, in route language, for the other platform_* tools (#3106).
# Both lists come from the router, so they grow with the platform. The write list is long: filter it by area.
class Mcp::Tools::PlatformCatalog < Mcp::Tools::Base
  tool_name 'platform_catalog'
  description 'List what the platform can read (kind read: resources for platform_read, like "inboxes", "crm/pipelines", ' \
              '"contacts/:id") or do (kind write: actions for platform_action, like "POST crm/pipelines", "PATCH inboxes/:id"). ' \
              'Covers everything the account has: CRM, campaigns, automations, AI agents, inboxes, teams, help center and more. ' \
              'Use filter to keep only the entries that contain a word, like "crm" or "campaign".'
  scope 'platform:read'
  annotations(read_only_hint: true, destructive_hint: false, open_world_hint: false)
  input_schema(
    properties: {
      kind: { type: 'string', enum: %w[read write], description: 'read for platform_read, write for platform_action.' },
      filter: { type: 'string', description: 'Only entries that contain this text.' }
    },
    required: ['kind']
  )

  def self.perform(kind:, filter: nil)
    entries = kind == 'write' ? acoes.catalogo : consulta.catalogo
    needle = filter.to_s.strip.downcase
    entries = entries.select { |entry| entry.downcase.include?(needle) } if needle.present?

    respond(kind: kind, entries: entries)
  end
end
