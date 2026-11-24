class Mcp::Tools::CreateContact < Mcp::Tools::Base
  tool_name 'create_contact'
  description 'Create a contact. Search first with search_contacts to avoid a duplicate. Phone numbers use the international ' \
              'format with country code, like +5511999999999.'
  scope 'contacts:write'
  annotations(read_only_hint: false, destructive_hint: false, open_world_hint: false)
  input_schema(
    properties: {
      name: { type: 'string', minLength: 1 },
      email: { type: 'string' },
      phone_number: { type: 'string', description: 'International format, like +5511999999999.' },
      identifier: { type: 'string', description: 'An id of the contact in another system.' },
      custom_attributes: { type: 'object', description: 'Values for the custom attributes of the account, by attribute key.' }
    },
    required: ['name']
  )

  def self.perform(name:, **attributes)
    authorize(Contact, :create?)
    error = internal_keys_error(attributes[:custom_attributes])
    return error if error

    contact = Current.account.contacts.create!(attributes.slice(:email, :phone_number, :identifier, :custom_attributes).merge(name: name))

    respond(contact_summary(contact))
  end
end
