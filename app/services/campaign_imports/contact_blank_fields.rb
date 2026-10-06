# What an imported row may add to a contact (Públicos, #992): an existing contact only gains
# what it lacks, and an email already used by another contact of the account is left alone.
class CampaignImports::ContactBlankFields
  def initialize(account)
    @account = account
  end

  # Emails are compared without case, as Contact validates them.
  def contact_with_email(email)
    @account.contacts.where('LOWER(email) = ?', email.downcase).first
  end

  def fill!(contact, row)
    attributes = {
      name: (row[:name] if contact.name.blank?),
      phone_number: (row[:phone_number] if contact.phone_number.blank?),
      email: (row[:email] if contact.email.blank? && email_free?(row[:email]))
    }.compact_blank
    contact.update!(attributes) if attributes.any?
  end

  private

  def email_free?(email)
    email.present? && contact_with_email(email).nil?
  end
end
