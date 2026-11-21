class Mcp::Tools::AddContactNote < Mcp::Tools::Base
  tool_name 'add_contact_note'
  description 'Add a note to a contact. Notes are internal: the contact never sees them.'
  scope 'contacts:write'
  annotations(read_only_hint: false, destructive_hint: false, open_world_hint: false)
  input_schema(
    properties: {
      contact_id: { type: 'integer', description: 'The contact id from search_contacts.' },
      content: { type: 'string', minLength: 1 }
    },
    required: %w[contact_id content]
  )

  def self.perform(contact_id:, content:)
    contact = find_contact(contact_id)
    note = contact.notes.create!(account: Current.account, user: Current.user, content: content)

    respond(id: note.id, contact_id: contact.id, content: note.content, created_at: note.created_at.iso8601)
  end
end
