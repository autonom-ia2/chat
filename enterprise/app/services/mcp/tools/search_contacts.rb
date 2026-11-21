class Mcp::Tools::SearchContacts < Mcp::Tools::Base
  RESULTS_PER_PAGE = 15

  tool_name 'search_contacts'
  description "Find contacts by part of their name, email, phone number or identifier. Returns #{RESULTS_PER_PAGE} per page."
  scope 'contacts:read'
  annotations(read_only_hint: true, destructive_hint: false, open_world_hint: false)
  input_schema(
    properties: {
      query: { type: 'string', minLength: 2, description: 'Text to look for.' },
      page: { type: 'integer', minimum: 1 }
    },
    required: ['query']
  )

  def self.perform(query:, page: 1)
    authorize(Contact, :search?)
    contacts = Current.account.contacts.where(
      'name ILIKE :search OR email ILIKE :search OR phone_number ILIKE :search OR contacts.identifier ILIKE :search',
      search: "%#{Contact.sanitize_sql_like(query.strip)}%"
    ).order(:name).page(page).per(RESULTS_PER_PAGE)

    respond(contacts: contacts.map { |contact| contact_summary(contact) })
  end
end
