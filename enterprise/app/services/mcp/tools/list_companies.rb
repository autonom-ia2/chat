class Mcp::Tools::ListCompanies < Mcp::Tools::Base
  RESULTS_PER_PAGE = 25

  tool_name 'list_companies'
  description "List the companies of the account, #{RESULTS_PER_PAGE} per page. Pass search to find by name or domain."
  scope 'contacts:read'
  annotations(read_only_hint: true, destructive_hint: false, open_world_hint: false)
  input_schema(
    properties: {
      search: { type: 'string', description: 'Part of the name or the domain.' },
      page: { type: 'integer', minimum: 1 }
    }
  )

  def self.perform(search: nil, page: 1)
    companies = Current.account.companies.order(:name)
    if search.present?
      companies = companies.where('name ILIKE :search OR domain ILIKE :search', search: "%#{Company.sanitize_sql_like(search.strip)}%")
    end

    respond(companies: companies.page(page).per(RESULTS_PER_PAGE).map do |company|
      { id: company.id, name: company.name, domain: company.domain, description: company.description, contacts_count: company.contacts_count }
    end)
  end
end
