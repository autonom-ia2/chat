# A spreadsheet cell may hold more than one phone or email ("a@x.com; b@y.com",
# "(11) 98765-4321 / (11) 3456-7890"). The first part that the block accepts is the contact; the
# whole cell is tried first, so a single value never changes meaning. Used by the customer_base
# reading (CampaignImports::ContactReading).
#
# excel_serial (#1331): an XLSX number cell whose style shows a date or a time keeps the Excel serial
# number ("46309", "0.625"). The reader turns it into text anyone reads back the same way, for the
# audience columns and for the customer base: "2026-10-14", "15:00" or "2026-10-14 15:00" (ISO 8601,
# the wall time written in the sheet, no time zone).
module CampaignImports::CellValues
  SEPARATORS = [';', ',', '/', '|', "\n"].freeze
  SERIAL_KINDS = %i[date time datetime].freeze
  # Day 0 of the 1900 system is 1899-12-30: Excel counts a 29/02/1900 that never existed, so serials
  # from 61 on (01/03/1900) land right. Earlier serials are one day off, as in every reader that skips
  # the fake day; no customer sheet holds dates from early 1900.
  EXCEL_EPOCH = Date.new(1899, 12, 30)
  EXCEL_EPOCH_1904 = Date.new(1904, 1, 1)
  MINUTES_PER_DAY = 1440

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

  # kind: :date, :time or :datetime (CampaignImports::XlsxDateFormats). A value that is not a finite,
  # non-negative number stays as it is.
  def excel_serial(value, kind, date1904: false)
    serial = Float(value.to_s, exception: false)
    return value if serial.nil? || !serial.finite? || serial.negative? || SERIAL_KINDS.exclude?(kind)

    days, minutes = serial_parts(serial, kind)
    date = (date1904 ? EXCEL_EPOCH_1904 : EXCEL_EPOCH) + days
    time = format('%<hours>02d:%<minutes>02d', hours: minutes / 60, minutes: minutes % 60)
    { date: date.iso8601, time: time, datetime: "#{date.iso8601} #{time}" }.fetch(kind)
  end

  # Whole days and the minute of the day. A date alone ignores the hour; a time rounds to the
  # minute, and 23:59:59.9 rolls over to the next day instead of reading 24:00.
  def serial_parts(serial, kind)
    days = serial.floor
    return [days, 0] if kind == :date

    minutes = ((serial - days) * MINUTES_PER_DAY).round
    minutes == MINUTES_PER_DAY ? [days + 1, 0] : [days, minutes]
  end

  def parts(value)
    pieces = SEPARATORS.reduce([value.to_s]) { |found, separator| found.flat_map { |piece| piece.split(separator) } }
    pieces = pieces.map(&:strip).reject(&:empty?)
    pieces.size > 1 ? pieces : []
  end
end
