# One spreadsheet row written to the account's contacts (#1006, #2771): the core the Importer runs
# for every row, shared with the automation step "para_cada" (G24), so the screen and the step follow
# one rule.
#
# - The phone (with or without the 9th digit, ContactMatcher) wins, then the e-mail without case.
#   Never a duplicate contact.
# - A new contact gets the row's name, phone and e-mail. An existing one only gains what it lacks
#   (ContactBlankFields): a name, phone or e-mail already filled is never overwritten.
# - With a linker (CompanyLinker), the company named in the row goes to a contact without one; a
#   contact of another company is kept as is.
# - The actor must pass the Contacts screen's import question (ContactPolicy#import?: administrator,
#   or a custom role with contact_manage), asked again here because the write runs later, in a job
#   or an automation. Who left the account can't import. Without it, #write raises NotAllowed
#   before touching anything.
class CampaignImports::ContactRow
  NotAllowed = Class.new(StandardError)
  Result = Struct.new(:contact, :existing, :company, keyword_init: true)
  # Públicos and the campaign base flow are not a contact import: their controller asks
  # CampaignImportPolicy, and the Importer passes this instead of an actor.
  UNCHECKED = :unchecked

  def self.allowed?(account_user)
    return false if account_user.nil?

    contexto = { user: account_user.user, account: account_user.account, account_user: account_user }
    ContactPolicy.new(contexto, Contact).import?
  end

  # account_user: who imports, in this account (nil when that person left it), or UNCHECKED.
  def initialize(account, account_user:, linker: nil)
    @account = account
    @account_user = account_user
    @linker = linker
  end

  def allowed?
    return @allowed if defined?(@allowed)

    @allowed = @account_user == UNCHECKED || self.class.allowed?(@account_user)
  end

  # Result: the contact, whether it already existed, and the CompanyLinker::Result (nil without a
  # linker). row: { name:, phone_number: (normalized, with +), email:, company_name: }.
  def write(row)
    raise NotAllowed unless allowed?

    contact = find(row)
    existing = contact.present?
    contact ||= @account.contacts.create!(name: row[:name], phone_number: row[:phone_number], email: row[:email])
    blank_fields.fill!(contact, row)
    Result.new(contact: contact, existing: existing, company: link_company(contact, row))
  end

  private

  def find(row)
    contact = matcher.find(row[:phone_number]) if row[:phone_number].present?
    contact || (blank_fields.contact_with_email(row[:email]) if row[:email].present?)
  end

  # Companies come only from the row: Enterprise's e-mail domain association is skipped, so a
  # switched-off import creates none.
  def link_company(contact, row)
    return if @linker.nil?

    contact.skip_company_auto_association = true if contact.respond_to?(:skip_company_auto_association=)
    @linker.link(contact, company_name: row[:company_name], email: row[:email])
  end

  def matcher = @matcher ||= CampaignImports::ContactMatcher.new(@account)

  def blank_fields = @blank_fields ||= CampaignImports::ContactBlankFields.new(@account)
end
