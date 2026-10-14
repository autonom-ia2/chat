# What a column's phone values say about their country, as counts only (no value leaves the server).
# Jev reads these next to the headers to decide whether the phone column is Brazilian (#1246):
# - complete_brazilian_mobile_count: cells that already hold a whole Brazilian mobile (DDD + 9 + 8 digits);
# - legacy_mobile_count: cells that are a Brazilian mobile only if the ninth digit is added to a 10-digit
#   number without country code — the ones whose digits alone cannot tell the country;
# - country_code_55_count / other_country_code_count: values written with "+55" or another "+code".
# A cell counts as the validator reads it: the first valid part, without the ninth digit first.
class CampaignImports::PhoneEvidence
  KEYS = %i[complete_brazilian_mobile_count legacy_mobile_count country_code_55_count other_country_code_count].freeze

  # reading: the customer_base ContactReading.
  def initialize(values, reading)
    @values = values
    @strict = reading.with_legacy_mobiles(false)
    @with_legacy = reading.with_legacy_mobiles(true)
  end

  def to_h
    complete = @values.count { |value| @strict.phone?(value) }
    codes = @values.filter_map { |value| country_code(value) }
    {
      complete_brazilian_mobile_count: complete,
      legacy_mobile_count: @values.count { |value| @with_legacy.phone?(value) } - complete,
      country_code_55_count: codes.count('55'),
      other_country_code_count: codes.count { |code| code != '55' }
    }
  end

  private

  # The first two digits after "+", or nil when the value has no "+".
  def country_code(value)
    plus = value.index('+')
    plus && value[plus..].delete('^0-9')[0, 2]
  end
end
