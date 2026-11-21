class Mcp::Tools::GetContact < Mcp::Tools::Base
  CONVERSATION_LIMIT = 10
  NOTE_LIMIT = 20

  tool_name 'get_contact'
  description "Read one contact: details, custom attributes, labels, company, the latest #{NOTE_LIMIT} notes " \
              "and the latest #{CONVERSATION_LIMIT} conversations."
  scope 'contacts:read'
  annotations(read_only_hint: true, destructive_hint: false, open_world_hint: false)
  input_schema(
    properties: { contact_id: { type: 'integer', description: 'The contact id from search_contacts.' } },
    required: ['contact_id']
  )

  def self.perform(contact_id:)
    contact = find_contact(contact_id)
    conversations = contact.conversations.order(last_activity_at: :desc).limit(CONVERSATION_LIMIT)
    notes = contact.notes.order(created_at: :desc).limit(NOTE_LIMIT).includes(:user)

    respond(contact_summary(contact).merge(
              labels: contact.label_list,
              custom_attributes: contact.custom_attributes,
              additional_attributes: contact.additional_attributes,
              company_id: contact.try(:company_id),
              conversations: conversations.map { |conversation| conversation_summary(conversation) },
              notes: notes.map { |note| { id: note.id, content: note.content, author: note.user&.name, created_at: note.created_at.iso8601 } }
            ))
  end
end
