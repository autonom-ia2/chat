# A spreadsheet cell may hold more than one phone or email ("a@x.com; b@y.com",
# "(11) 98765-4321 / (11) 3456-7890"). The first part that the normalizer accepts is the
# contact; the whole cell is tried first, so a single value never changes meaning.
module CampaignImports::CellValues
  SEPARATORS = [';', ',', '/', '|', "\n"].freeze

  module_function

  # normalizer: CampaignImports::PhoneNormalizer or EmailCampaigns::EmailNormalizer (anything with normalize! and Error).
  # Raises the error of the whole cell when no part is valid, so the row keeps the same reason.
  def normalize!(normalizer, value)
    normalizer.normalize!(value)
  rescue normalizer::Error => e
    parts(value).each do |part|
      return normalizer.normalize!(part)
    rescue normalizer::Error
      next
    end
    raise e
  end

  # Every address of the cell masked ("a**@x.com; b**@y.com"): no part is stored in clear.
  def masked_emails(value)
    addresses = parts(value).presence || [value.to_s.strip]
    addresses.map { |address| EmailCampaigns::EmailNormalizer.mask(address.downcase) }.join('; ')
  end

  def parts(value)
    pieces = SEPARATORS.reduce([value.to_s]) { |found, separator| found.flat_map { |piece| piece.split(separator) } }
    pieces = pieces.map(&:strip).reject(&:empty?)
    pieces.size > 1 ? pieces : []
  end
end
