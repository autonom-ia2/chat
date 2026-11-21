class Mcp::Tools::GetCompany < Mcp::Tools::Base
  CONTACT_LIMIT = 50

  tool_name 'get_company'
  description "Read one company with its custom attributes and up to #{CONTACT_LIMIT} of its contacts."
  scope 'contacts:read'
  annotations(read_only_hint: true, destructive_hint: false, open_world_hint: false)
  input_schema(
    properties: { company_id: { type: 'integer', description: 'The company id from list_companies.' } },
    required: ['company_id']
  )

  def self.perform(company_id:)
    company = Current.account.companies.find(company_id)

    respond(id: company.id, name: company.name, domain: company.domain, description: company.description,
            custom_attributes: company.custom_attributes,
            contacts: company.contacts.order(:name).limit(CONTACT_LIMIT).map { |contact| contact_summary(contact) })
  end
end
