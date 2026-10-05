# Companies inside an audience import (#998, PRD §8.2 "Empresa"). The Importer uses one
# instance per run, only for Públicos; the old campaign base flow never touches companies.
class CampaignImports::ImportCompanies
  def initialize(campaign_import)
    @campaign_import = campaign_import
    @linker = CampaignImports::CompanyLinker.new(campaign_import.account, enabled: campaign_import.create_companies?)
  end

  # One query per block for the companies its rows resolve to.
  def prepare(block)
    linker.prepare(block)
  end

  # Inside the row savepoint, after the contact exists. Companies come only from the
  # spreadsheet's company column: Enterprise's e-mail domain association is skipped for every
  # audience row, so a switched-off import creates none (C5) and the preview stays true.
  # Returns the attributes to keep on the import row.
  def link(contact, row)
    contact.skip_company_auto_association = true if contact.respond_to?(:skip_company_auto_association=)
    result = linker.link(contact, company_name: row[:company_name], email: row[:email])
    { company_id: result.company&.id, company_result: result.status.to_s }
  end

  # Final numbers come from the persisted rows, so a retried import (new linker, rows already
  # imported skipped) still reports the whole import. A company counts as reused only when no
  # row of this import created it.
  def counters
    rows = campaign_import.campaign_import_rows.status_imported
    by_result = rows.group(:company_result).count
    created_ids = rows.where(company_result: 'created').select(:company_id)
    {
      companies_created_count: by_result.fetch('created', 0),
      companies_reused_count: rows.where(company_result: 'reused').where.not(company_id: created_ids).distinct.count(:company_id),
      companies_kept_count: by_result.fetch('kept_other', 0),
      company_contacts_linked_count: by_result.fetch('created', 0) + by_result.fetch('reused', 0)
    }
  end

  private

  attr_reader :campaign_import, :linker
end
