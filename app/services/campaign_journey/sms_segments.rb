# How many SMS parts a text takes (#1004, PRD §6.3 "contador de caracteres/partes"). Plain
# character lookups, no regular expressions. The screen counts with the same rules (contract in
# docs/campaigns/publicos/api-1004.md §4).
#
# - GSM-7 when every character is in the GSM 03.38 basic table or its extension table; an
#   extension character (^ { } \ [ ~ ] | € and form feed) takes 2 units. 1 part up to 160 units;
#   longer texts go in parts of 153 units.
# - Otherwise UCS-2: units are UTF-16 code units (an emoji outside the basic plane takes 2).
#   1 part up to 70 units; longer texts go in parts of 67 units.
# - A 2-unit character is never split between parts.
module CampaignJourney::SmsSegments
  GSM_BASIC = Set.new(
    "@£$¥èéùìòÇ\nØø\rÅåΔ_ΦΓΛΩΠΨΣΘΞÆæßÉ !\"#¤%&'()*+,-./0123456789:;<=>?¡" \
    'ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÑÜ§¿abcdefghijklmnopqrstuvwxyzäöñüà'.chars
  ).freeze
  GSM_EXTENSION = Set.new("\f^{}\\[~]|€".chars).freeze
  LIMITS = {
    'GSM-7' => { single: 160, multi: 153 },
    'UCS-2' => { single: 70, multi: 67 }
  }.freeze
  BASIC_PLANE_MAX = 0xFFFF

  module_function

  # => { encoding: 'GSM-7', characters: 12, units: 12, segments: 1, per_segment: 160 }
  def count(text)
    chars = text.to_s.chars
    encoding = chars.all? { |char| gsm?(char) } ? 'GSM-7' : 'UCS-2'
    sizes = chars.map { |char| units_of(char, encoding) }
    limit = LIMITS[encoding]
    total = sizes.sum
    per_segment = total > limit[:single] ? limit[:multi] : limit[:single]
    { encoding: encoding, characters: chars.size, units: total, segments: segments_for(sizes, total, limit),
      per_segment: per_segment }
  end

  def gsm?(char)
    GSM_BASIC.include?(char) || GSM_EXTENSION.include?(char)
  end

  def units_of(char, encoding)
    if encoding == 'GSM-7'
      GSM_EXTENSION.include?(char) ? 2 : 1
    else
      char.ord > BASIC_PLANE_MAX ? 2 : 1
    end
  end

  # Fills parts greedily without splitting a 2-unit character.
  def segments_for(sizes, total, limit)
    return 0 if total.zero?
    return 1 if total <= limit[:single]

    segments = 1
    used = 0
    sizes.each do |size|
      if used + size > limit[:multi]
        segments += 1
        used = 0
      end
      used += size
    end
    segments
  end
end
