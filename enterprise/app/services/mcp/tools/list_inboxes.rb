class Mcp::Tools::ListInboxes < Mcp::Tools::Base
  tool_name 'list_inboxes'
  description 'List the inboxes (channels such as WhatsApp, e-mail, Instagram or website chat) of the account. ' \
              'Use the id to filter list_conversations.'
  scope 'conversations:read'
  annotations(read_only_hint: true, destructive_hint: false, open_world_hint: false)
  input_schema(properties: {})

  def self.perform
    inboxes = Current.account.inboxes.order(:name)

    respond(inboxes: inboxes.map { |inbox| { id: inbox.id, name: inbox.name, channel: inbox.channel_type.to_s.delete_prefix('Channel::') } })
  end
end
