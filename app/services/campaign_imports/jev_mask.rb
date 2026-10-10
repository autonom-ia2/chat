# How a value that looks like a phone or an email goes to Jev (#1246, shape decided by Rodrigo): the
# country code and the area code (DDD) stay visible, every other digit becomes 0 and the punctuation
# stays, so "(11) 98765-4321" goes as "(11) 00000-0000" and "+1 917-555-1234" as "+1 917-000-0000".
# An email keeps its domain and masks the local part ("joao@empresa.com.br" → "aaaa@empresa.com.br").
# Country, area code and domain tell Jev the country; none of them identifies a person.
module CampaignImports::JevMask
  PHONE_DIGITS = 8
  LONGEST_AREA_GROUP = 4 # "(11)", "011", "917", "0055"
  LONGEST_AREA_CODE = 3

  module_function

  # The masked value, or nil when it looks like neither a phone nor an email.
  def mask(value)
    text = value.to_s
    return email(text) if text.include?('@')

    phone(text) if text.count('0-9') >= PHONE_DIGITS
  end

  def email(text)
    addresses = CampaignImports::CellValues.parts(text).presence || [text.strip]
    addresses.map do |address|
      local, at, domain = address.partition('@')
      "#{masked_text(local)}#{at}#{domain}"
    end.join('; ')
  end

  def phone(text)
    visible = visible_digits(text)
    seen = 0
    text.each_char.map do |char|
      next masked_text(char) unless digit?(char)

      seen += 1
      seen <= visible ? char : '0'
    end.join
  end

  # Glued digits keep the area code only (+ the country code when written with "+"); separated digits keep
  # the first group when it is short enough to be an area code, and the next one after a country code.
  def visible_digits(text)
    groups = digit_groups(text)
    international = text.include?('+')
    return [groups.first.length, international ? 4 : 2].min if groups.one?
    return 0 if groups.first.length > LONGEST_AREA_GROUP

    groups.first.length + area_after_country(groups, international)
  end

  # "+55 11 …", "+1 917 …", "0055 11 …": the group after the country code is the area code.
  def area_after_country(groups, international)
    after_country = international || without_leading_zeros(groups.first) == '55'
    after_country && groups[1].length <= LONGEST_AREA_CODE ? groups[1].length : 0
  end

  def digit_groups(text)
    text.each_char.chunk_while { |left, right| digit?(left) == digit?(right) }.map(&:join).select { |group| digit?(group[0]) }
  end

  def masked_text(text)
    text.each_char.map { |char| CampaignImports::ColumnProfiler::EXAMPLE_MASK[char] }.join
  end

  def without_leading_zeros(group)
    group = group[1..] while group.start_with?('0')
    group
  end

  def digit?(char)
    char.between?('0', '9')
  end
end
