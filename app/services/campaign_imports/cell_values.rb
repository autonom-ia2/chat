# A spreadsheet cell may hold more than one phone or email ("a@x.com; b@y.com",
# "(11) 98765-4321 / (11) 3456-7890"). The first part that the block accepts is the contact; the
# whole cell is tried first, so a single value never changes meaning. Used by the customer_base
# reading (CampaignImports::ContactReading).
module CampaignImports::CellValues
  SEPARATORS = [';', ',', '/', '|', "\n"].freeze

  module_function

  # error: the class the block raises for an invalid value. Raises the error of the whole cell
  # when no part is valid, so the row keeps the same reason.
  def first_valid(value, error)
    yield(value)
  rescue error => e
    parts(value).each do |part|
      return yield(part)
    rescue error
      next
    end
    raise e
  end

  # Every address of the cell masked ("a**@x.com; b**@y.com"): no part is stored in clear.
  def masked_emails(value)
    addresses = parts(value).presence || [value.to_s.strip]
    addresses.map { |address| EmailCampaigns::EmailNormalizer.mask(address.downcase) }.join('; ')
  end

  # Every number of the cell masked on its own (country code and last 4 digits, PhoneMask).
  def masked_phones(value)
    numbers = parts(value).presence || [value.to_s.strip]
    numbers.map { |number| CampaignImports::PhoneNormalizer.mask_raw(number) }.join('; ')
  end

  def parts(value)
    pieces = SEPARATORS.reduce([value.to_s]) { |found, separator| found.flat_map { |piece| piece.split(separator) } }
    pieces = pieces.map(&:strip).reject(&:empty?)
    pieces.size > 1 ? pieces : []
  end
end
