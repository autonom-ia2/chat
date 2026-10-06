# Companies from a spreadsheet import (#998, PRD §8.2 "Empresa").
#
# One instance per import. For each row it finds or creates the company named in the
# spreadsheet and links it to the row's contact, without ever overwriting a company the
# contact already has.
#
# - Lookup (CompanyResolver, shared with CompanyPreview): by the domain of a business e-mail
#   when a company of the account has that domain; otherwise by normalized name (spaces
#   collapsed, case- and accent-insensitive, exact comparison). Not found: creates the
#   company with the name as written (trimmed).
# - Contact without company: linked. Same company: nothing. Another company: kept.
# - One company per normalized name per import: names are indexed in memory once per
#   import (id, name, domain of the account's companies), so a block of rows costs one
#   query to load the records it needs, plus the writes.
# - A row whose savepoint rolls back forgets what it created and counted, so later rows do
#   not point at a company that no longer exists.
#
# Company exists only in the Enterprise overlay and behind the `companies` account flag;
# without either, every row resolves to :none and nothing is written.
class CampaignImports::CompanyLinker
  FEATURE = 'companies'.freeze
  STATUSES = %i[created reused kept_other none].freeze

  Result = Struct.new(:status, :company, :linked, keyword_init: true) do
    def linked?
      linked == true
    end
  end

  def self.available?(account)
    defined?(Company).present? && account.feature_enabled?(FEATURE)
  end

  # "Corretora  São Paulo " and "corretora sao paulo" share the same key.
  def self.normalize_name(value)
    CampaignImports::CompanyResolver.normalize_name(value)
  end

  # enabled: the "Criar e ligar" switch of the import. Off means every row is :none.
  def initialize(account, enabled: true)
    @account = account
    @active = enabled && self.class.available?(account)
    @resolver = CampaignImports::CompanyResolver.new(account)
    @created_ids = Set.new
    @counts = { companies_created: 0, contacts_linked: 0, contacts_kept: 0 }
    @reused_rows = Hash.new(0)
  end

  def active?
    @active
  end

  # rows: [{ company_name:, email: }, ...] for one block. Loads the companies those rows
  # resolve to in a single query. Optional: #link works without it, one query per company.
  def prepare(rows)
    return self unless active?

    ids = Array(rows).filter_map { |row| resolver.existing_company_id(row[:company_name], row[:email]) }.uniq - companies_by_id.keys
    account.companies.where(id: ids).find_each { |company| companies_by_id[company.id] = company } if ids.any?
    self
  end

  def link(contact, company_name:, email: nil)
    display_name = CampaignImports::CompanyResolver.clean_name(company_name)
    return Result.new(status: :none, linked: false) if !active? || display_name.nil?

    company = find_company(display_name, email)
    return keep_other(company) if contact.company_id.present? && contact.company_id != company&.id
    return reuse(contact, company) if company

    create_and_link(contact, display_name)
  end

  # Distinct companies created, distinct pre-existing companies used, rows linked, rows kept.
  def summary
    @counts.merge(companies_reused: @reused_rows.count { |_id, rows| rows.positive? })
  end

  private

  attr_reader :account, :resolver

  def keep_other(company)
    record!(:contacts_kept, 1)
    Result.new(status: :kept_other, company: company, linked: false)
  end

  def reuse(contact, company)
    linked = contact.company_id.nil?
    assign!(contact, company) if linked
    reused_existing = @created_ids.exclude?(company.id)
    count_reuse!(company.id) if reused_existing
    record!(:contacts_linked, 1) if linked
    Result.new(status: :reused, company: company, linked: linked)
  end

  def create_and_link(contact, display_name)
    company = account.companies.create!(name: display_name)
    remember_created!(company, display_name)
    assign!(contact, company)
    record!(:companies_created, 1)
    record!(:contacts_linked, 1)
    Result.new(status: :created, company: company, linked: true)
  end

  # The flag stops Enterprise's after_commit from creating a second company from the e-mail.
  def assign!(contact, company)
    contact.skip_company_auto_association = true
    Companies::ContactMembershipService.new(company: company).assign(contact: contact)
  end

  def find_company(display_name, email)
    id = resolver.existing_company_id(display_name, email)
    return if id.nil?

    companies_by_id[id] ||= account.companies.find(id)
  end

  def companies_by_id
    @companies_by_id ||= {}
  end

  def remember_created!(company, display_name)
    resolver.remember(display_name, company.id)
    companies_by_id[company.id] = company
    @created_ids << company.id
    on_rollback do
      resolver.forget(display_name)
      companies_by_id.delete(company.id)
      @created_ids.delete(company.id)
    end
  end

  def record!(counter, amount)
    @counts[counter] += amount
    on_rollback { @counts[counter] -= amount }
  end

  def count_reuse!(company_id)
    @reused_rows[company_id] += 1
    on_rollback { @reused_rows[company_id] -= 1 }
  end

  # Fires when the caller's transaction (or the row savepoint) rolls back; no-op outside one.
  def on_rollback(&)
    ActiveRecord::Base.current_transaction.after_rollback(&)
  end
end
