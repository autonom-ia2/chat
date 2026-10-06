# Importar contatos (#1006): which valid rows match a contact the account already has, with the
# importer's rule (phone with or without the 9th digit, then e-mail without case). Read-only;
# the screen shows "N já eram seus contatos · M novos" and which attribute values a contact
# keeps (ContactImports::AttributeProblems).
class ContactImports::ExistingContacts
  SLICE = 1000

  # rows: [{ row_number:, normalized_phone:, email: }, ...] — the valid rows.
  def initialize(account, rows)
    @account = account
    @rows = rows
    @matcher = CampaignImports::ContactMatcher.new(account)
  end

  def count
    custom_attributes_by_row.size
  end

  # { row_number => custom_attributes of the contact that row will reuse }; new contacts left out.
  def custom_attributes_by_row
    @custom_attributes_by_row ||= @rows.each_with_object({}) do |row, found|
      match = by_phone(row) || (row[:email].present? && by_email[row[:email].downcase])
      found[row[:row_number]] = match.to_h if match
    end
  end

  private

  def by_phone(row)
    return unless row[:normalized_phone]

    @matcher.candidates(row[:normalized_phone]).lazy.filter_map { |number| phones[number] }.first
  end

  def phones
    @phones ||= load(@rows.filter_map { |row| row[:normalized_phone] }.flat_map { |phone| @matcher.candidates(phone) }.uniq) do |slice|
      @account.contacts.where(phone_number: slice).pluck(:phone_number, :custom_attributes)
    end
  end

  def by_email
    @by_email ||= load(@rows.filter_map { |row| row[:email]&.downcase }.uniq) do |slice|
      @account.contacts.where('LOWER(email) IN (?)', slice).pluck(Arel.sql('LOWER(email)'), :custom_attributes)
    end
  end

  def load(keys)
    keys.each_slice(SLICE).with_object({}) do |slice, found|
      yield(slice).each { |key, custom_attributes| found[key] ||= custom_attributes || {} }
    end
  end
end
