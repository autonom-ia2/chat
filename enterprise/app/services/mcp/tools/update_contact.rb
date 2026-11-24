class Mcp::Tools::UpdateContact < Mcp::Tools::Base
  tool_name 'update_contact'
  description 'Change a contact. Only the fields you pass are changed. custom_attributes are merged into the existing ones. ' \
              'labels replaces every label of the contact, so include the ones to keep.'
  scope 'contacts:write'
  annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: true, open_world_hint: false)
  input_schema(
    properties: {
      contact_id: { type: 'integer', description: 'The contact id from search_contacts.' },
      name: { type: 'string', minLength: 1 },
      email: { type: 'string' },
      phone_number: { type: 'string', description: 'International format, like +5511999999999.' },
      identifier: { type: 'string' },
      custom_attributes: { type: 'object', description: 'Values to set, by attribute key.' },
      labels: { type: 'array', items: { type: 'string' }, description: 'Only labels of the account (list_labels).' }
    },
    required: ['contact_id']
  )

  def self.perform(contact_id:, labels: nil, custom_attributes: nil, **attributes)
    contact = find_contact(contact_id)
    authorize(contact, :update?)
    error = (labels && unknown_labels_error(labels)) || internal_keys_error(custom_attributes)
    return error if error

    contact.with_lock do
      contact.assign_attributes(attributes.slice(:name, :email, :phone_number, :identifier))
      contact.custom_attributes = contact.custom_attributes.merge(custom_attributes.stringify_keys) if custom_attributes
      contact.save!
    end
    contact.update_labels(labels) if labels

    contact.reload
    custom = Relationships::ChavesInternas.sem_internas(contact.custom_attributes)
    respond(contact_summary(contact).merge(labels: contact.label_list, custom_attributes: custom))
  end
end
