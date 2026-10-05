# Importar contatos (#1006): how many valid rows match a contact the account already has, with
# the importer's rule (phone with or without the 9th digit, then e-mail without case). Read-only;
# the screen shows "N já eram seus contatos · M novos" before saving.
class ContactImports::ExistingContacts
  SLICE = 1000

  # rows: [{ normalized_phone:, email: }, ...] — the valid rows.
  def initialize(account, rows)
    @account = account
    @rows = rows
    @matcher = CampaignImports::ContactMatcher.new(account)
  end

  def count
    phones = known_phones
    emails = known_emails
    @rows.count do |row|
      by_phone = row[:normalized_phone] && @matcher.candidates(row[:normalized_phone]).any? { |number| phones.include?(number) }
      by_phone || (row[:email].present? && emails.include?(row[:email].downcase))
    end
  end

  private

  def known_phones
    numbers = @rows.filter_map { |row| row[:normalized_phone] }.flat_map { |phone| @matcher.candidates(phone) }.uniq
    numbers.each_slice(SLICE).flat_map { |slice| @account.contacts.where(phone_number: slice).pluck(:phone_number) }.to_set
  end

  def known_emails
    emails = @rows.filter_map { |row| row[:email]&.downcase }.uniq
    emails.each_slice(SLICE).flat_map do |slice|
      @account.contacts.where('LOWER(email) IN (?)', slice).pluck(Arel.sql('LOWER(email)'))
    end.to_set
  end
end
