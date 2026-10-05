# Which existing company a spreadsheet row points to (#998, PRD §8.2 "Empresa"). Read-only:
# shared by CompanyLinker (import) and CompanyPreview (numbers shown before saving), so both
# follow exactly the same rules.
#
# - By the domain of a business e-mail, when a company of the account has that domain.
# - Otherwise by normalized name: NFKD, accents removed, downcase, whitespace collapsed;
#   exact comparison, punctuation kept. Oldest company wins when the account has duplicates.
#
# The indexes (id, name, domain of the account's companies) are loaded once, on first use.
class CampaignImports::CompanyResolver
  EMAIL_SEPARATOR = '@'.freeze
  COMBINING_MARKS = (0x0300..0x036f)

  # "Corretora  São Paulo " and "corretora sao paulo" share the same key.
  def self.normalize_name(value)
    value.to_s.unicode_normalize(:nfkd).each_char.reject { |char| COMBINING_MARKS.cover?(char.ord) }.join.downcase.split.join(' ')
  end

  # The name as it will be stored: trimmed and cut to the company name limit; nil when blank.
  def self.clean_name(value)
    value.to_s.strip.first(Limits::COMPANY_NAME_LENGTH_LIMIT).strip.presence
  end

  def initialize(account)
    @account = account
  end

  def existing_company_id(company_name, email)
    display_name = self.class.clean_name(company_name)
    return if display_name.nil?

    id_for_email_domain(email) || name_index[self.class.normalize_name(display_name)]
  end

  # A company created during the import becomes findable by its name (one per name per import).
  def remember(display_name, company_id)
    name_index[self.class.normalize_name(display_name)] = company_id
  end

  def forget(display_name)
    name_index.delete(self.class.normalize_name(display_name))
  end

  private

  attr_reader :account

  def id_for_email_domain(email)
    domain = email_domain(email)
    id = domain && domain_index[domain]
    id if id && Companies::BusinessEmailDetectorService.new(email.to_s.strip).perform
  end

  def email_domain(email)
    parts = email.to_s.strip.downcase.split(EMAIL_SEPARATOR)
    parts.last.presence if parts.size == 2 && parts.first.present?
  end

  def name_index
    load_indexes if @name_index.nil?
    @name_index
  end

  def domain_index
    load_indexes if @domain_index.nil?
    @domain_index
  end

  def load_indexes
    @name_index = {}
    @domain_index = {}
    account.companies.order(:id).pluck(:id, :name, :domain).each do |id, name, domain|
      @name_index[self.class.normalize_name(name)] ||= id
      @domain_index[domain.downcase] ||= id if domain.present?
    end
  end
end
