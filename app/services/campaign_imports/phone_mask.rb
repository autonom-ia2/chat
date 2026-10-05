# The only phone mask of the campaign features (#993, decision of 05/10): the country code and
# the last 4 digits, nothing else — "+55 •• •••••-7890". Used by audience rows, error CSVs,
# problem rows and WhatsApp API recipients. Numbers typed without a country code are Brazilian
# (imports run with default_country BR); up to 4 digits show nothing.
module CampaignImports::PhoneMask
  BULLET = '•'.freeze
  DEFAULT_COUNTRY = '55'.freeze
  VISIBLE_DIGITS = 4
  # Brazilian national number: 2-digit area code + 8 or 9 digits.
  NATIONAL_LENGTHS = [10, 11].freeze
  AREA_CODE_LENGTH = 2

  module_function

  def mask(phone_number)
    digits = phone_number.to_s.each_char.select { |char| char.between?('0', '9') }.join
    return '' if digits.empty?
    return BULLET * digits.length if digits.length <= VISIBLE_DIGITS

    country, national = split_country(digits, international: phone_number.to_s.strip.start_with?('+'))
    "+#{country} #{masked_national(national)}"
  end

  # "+1 415…" keeps its own country; a number without "+" is Brazilian unless it is too long.
  def split_country(digits, international:)
    return [DEFAULT_COUNTRY, digits.delete_prefix(DEFAULT_COUNTRY)] if digits.start_with?(DEFAULT_COUNTRY) && digits.length > NATIONAL_LENGTHS.max
    return [DEFAULT_COUNTRY, digits] unless international || digits.length > NATIONAL_LENGTHS.max

    country_length = [digits.length - NATIONAL_LENGTHS.min, 1].max
    [digits[0, country_length], digits[country_length..]]
  end

  def masked_national(national)
    last = national[-VISIBLE_DIGITS..]
    hidden = national.length - VISIBLE_DIGITS
    return "#{BULLET * hidden}#{last}" unless NATIONAL_LENGTHS.include?(national.length)

    subscriber_hidden = hidden - AREA_CODE_LENGTH
    "#{BULLET * AREA_CODE_LENGTH} #{BULLET * subscriber_hidden}-#{last}"
  end
end
