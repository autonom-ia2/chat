# What saving an audience will do with companies (#998, PRD §6.6 item 4), computed during
# validation without writing anything: new companies, companies that already existed,
# contacts that end up linked and contacts that keep another company ("mantidas").
#
# It walks the valid rows in import order with the importer's rules: CompanyResolver for the
# company, the importer's contact match (phone with or without the 9th digit, then e-mail
# without case) and CompanyLinker's decision per contact. Existing contacts are loaded in
# batches, so 20k rows cost a few queries. The numbers equal the import's final counters
# when companies and contacts do not change in between.
class CampaignImports::CompanyPreview
  SLICE = 1000

  # rows: [{ normalized_phone:, email:, company_name: }, ...] — the valid rows, in order.
  def initialize(account, rows)
    @account = account
    @rows = rows.select { |row| CampaignImports::CompanyResolver.clean_name(row[:company_name]) }
    @resolver = CampaignImports::CompanyResolver.new(account)
    @matcher = CampaignImports::ContactMatcher.new(account)
    @phone_candidates = {}
  end

  def perform
    return { 'available' => false } unless CampaignImports::CompanyLinker.available?(account)

    tally = { created: Set.new, reused: Set.new, linked: 0, kept: 0 }
    contact_companies = {}
    rows.each { |row| tally_row(row, tally, contact_companies) }
    {
      'available' => true, 'rows_with_company' => rows.size,
      'companies_created' => tally[:created].size, 'companies_reused' => tally[:reused].size,
      'contacts_linked' => tally[:linked], 'contacts_kept' => tally[:kept]
    }
  end

  private

  attr_reader :account, :rows, :resolver

  # A contact that already has another company keeps it; otherwise it is linked to the
  # existing company or to the one the import creates (once per normalized name).
  def tally_row(row, tally, contact_companies)
    existing_id = resolver.existing_company_id(row[:company_name], row[:email])
    company = existing_id || new_company_key(row[:company_name])
    contact_id, current = existing_contact(row)
    current = contact_companies.fetch(contact_id, current) if contact_id

    if current.present? && current != company
      tally[:kept] += 1
    else
      tally[:linked] += 1
      tally[existing_id ? :reused : :created] << company
      contact_companies[contact_id] = company if contact_id
    end
  end

  def new_company_key(company_name)
    "new:#{CampaignImports::CompanyResolver.normalize_name(CampaignImports::CompanyResolver.clean_name(company_name))}"
  end

  # [contact_id, company_id] of the contact the importer would reuse; nil for a new contact.
  def existing_contact(row)
    phone = row[:normalized_phone]
    by_phone = phone && candidates(phone).lazy.filter_map { |number| contacts_by_phone[number] }.first
    by_phone || (row[:email] && contacts_by_email[row[:email].downcase])
  end

  def candidates(phone)
    @phone_candidates[phone] ||= @matcher.candidates(phone)
  end

  def contacts_by_phone
    @contacts_by_phone ||= load_contacts(rows.filter_map { |row| row[:normalized_phone] }.flat_map { |phone| candidates(phone) }.uniq) do |slice|
      account.contacts.where(phone_number: slice).pluck(:phone_number, :id, :company_id)
    end
  end

  def contacts_by_email
    @contacts_by_email ||= load_contacts(rows.filter_map { |row| row[:email]&.downcase }.uniq) do |emails|
      account.contacts.where('LOWER(email) IN (?)', emails).pluck(Arel.sql('LOWER(email)'), :id, :company_id)
    end
  end

  def load_contacts(keys)
    keys.each_slice(SLICE).with_object({}) do |slice, found|
      yield(slice).each { |key, id, company_id| found[key] ||= [id, company_id] }
    end
  end
end
