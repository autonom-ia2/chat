# Importar contatos (#1006): turns a spreadsheet cell into the value a contact attribute of a
# given type holds, then checks it with the fork's typed-attribute validation
# (Relationships::ValueValidator: number, checkbox, list, link and ISO date). Returns INVALID
# when the cell does not fit; the import then leaves that value out and lists it as a problem.
#
# Conversions (string methods only):
# - number, currency, percent: "1.234,56", "R$ 10", "15%" and "10.5";
# - date: "2026-03-15", "15/03/2026" and Excel day numbers (XLSX date cells);
# - checkbox: sim/não, true/false, 1/0;
# - list: an option of the attribute, without case difference;
# - text and link: the cell as written (a link must be http(s)).
class ContactImports::AttributeValue
  INVALID = :invalid
  NUMBER_TYPES = %w[number currency percent].freeze
  TRUE_VALUES = %w[true sim s 1 yes].freeze
  FALSE_VALUES = %w[false não nao n 0 no].freeze
  EXCEL_EPOCH = Date.new(1899, 12, 30)
  EXCEL_DAYS = (1..80_000)

  def initialize(definition)
    @definition = definition
  end

  def cast(raw)
    text = raw.to_s.strip
    return INVALID if text.empty?

    value = convert(text)
    value == INVALID || !valid?(value) ? INVALID : value
  end

  private

  def type = @definition.attribute_display_type.to_s

  def convert(text)
    return number(text) if NUMBER_TYPES.include?(type)

    case type
    when 'date' then date(text)
    when 'checkbox' then checkbox(text)
    when 'list' then list(text)
    else text
    end
  end

  # Text, and any attribute with its own legacy pattern, are checked by the dashboard, not here.
  def valid?(value)
    return true if type == 'text' || @definition.regex_pattern.present?

    Relationships::ValueValidator.new(@definition).validate!(value)
    true
  rescue Relationships::Configuration::Invalid
    false
  end

  def number(text)
    plain = text.delete_prefix('R$').delete_suffix('%').delete(' ')
    plain = plain.delete('.').tr(',', '.') if plain.include?(',')
    number = Float(plain)
    number.modulo(1).zero? ? number.to_i : number
  rescue ArgumentError, TypeError
    INVALID
  end

  def date(text)
    parsed = excel_day(text) || Date.iso8601(text)
    parsed.iso8601
  rescue Date::Error
    brazilian_date(text)
  end

  def excel_day(text)
    days = Integer(text, exception: false)
    EXCEL_EPOCH + days if days && EXCEL_DAYS.cover?(days)
  end

  def brazilian_date(text)
    Date.strptime(text, '%d/%m/%Y').iso8601
  rescue Date::Error
    INVALID
  end

  def checkbox(text)
    word = text.downcase
    return true if TRUE_VALUES.include?(word)
    return false if FALSE_VALUES.include?(word)

    INVALID
  end

  def list(text)
    Array(@definition.attribute_values).map(&:to_s).find { |option| option.casecmp?(text) } || INVALID
  end
end
