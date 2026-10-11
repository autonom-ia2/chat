require 'rexml/document'

# Which cell styles of an XLSX show a number as a date or a time (#1331). In `xl/styles.xml` each cell
# style (`cellXfs/xf`, the `s` of a cell) points to a number format: a built-in id or a format code of
# the file (`numFmts`). The code is read character by character, without regex: quoted text, [brackets]
# (color, locale) and escaped characters are not date letters. A duration ([h]:mm) is not a time of day
# and stays a number. A styles part REXML cannot read is logged and leaves every number as it is
# (the import goes on as before #1331).
#
# kind_of(style_index) => :date, :time, :datetime, :time_seconds, :datetime_seconds or nil.
class CampaignImports::XlsxDateFormats
  # 27-36 and 50-58 are the dates of the East Asian locales.
  BUILT_IN = [14, 15, 16, 17, *27..36, *50..58].index_with(:date).merge(
    18 => :time, 20 => :time, 19 => :time_seconds, 21 => :time_seconds, 45 => :time_seconds, 47 => :time_seconds,
    22 => :datetime
  ).freeze
  DATE_LETTERS = %w[d y].freeze
  TIME_LETTERS = %w[h s].freeze
  ELAPSED_LETTERS = %w[h m s].freeze
  KINDS = { [true, true] => :datetime, [true, false] => :date, [false, true] => :time }.freeze
  WITH_SECONDS = { datetime: :datetime_seconds, time: :time_seconds }.freeze
  OPENERS = { '\\' => :escape, '_' => :escape, '*' => :escape, '"' => :quoted, '[' => :bracket }.freeze

  # xml: the content of xl/styles.xml, or nil when the file has none.
  def initialize(xml)
    @kinds = xml.to_s.empty? ? [] : style_kinds(REXML::Document.new(xml))
  rescue REXML::ParseException => e
    reason = e.message.lines.first.to_s.strip.first(200)
    Rails.logger.warn("[CampaignImports::XlsxDateFormats] styles.xml unreadable, numbers kept as written: #{reason}")
    @kinds = []
  end

  def kind_of(style_index)
    @kinds[style_index.to_i] if style_index
  end

  def self.kind_for_code(code)
    letters = visible_letters(code.to_s.downcase)
    return if letters.nil?

    time = TIME_LETTERS.intersect?(letters)
    date = DATE_LETTERS.intersect?(letters) || (letters.include?('m') && !time)
    kind = KINDS[[date, time]]
    letters.include?('s') ? WITH_SECONDS.fetch(kind, kind) : kind
  end

  # The letters of the first section of the code that the format prints, or nil for a duration.
  def self.visible_letters(code)
    letters = []
    brackets = []
    state = nil
    code.each_char do |char|
      break if state.nil? && char == ';'

      state, kept = step(state, char, brackets)
      letters << kept if kept
    end
    letters unless brackets.any? { |text| elapsed?(text) }
  end

  # => [the next state, the character the format prints or nil]
  def self.step(state, char, brackets)
    case state
    when :escape then [nil, nil]
    when :quoted then [char == '"' ? nil : :quoted, nil]
    when :bracket then close_or_extend(char, brackets)
    else
      opener = OPENERS[char]
      brackets << +'' if opener == :bracket
      [opener, opener ? nil : char]
    end
  end

  def self.close_or_extend(char, brackets)
    return [nil, nil] if char == ']'

    brackets.last << char
    [:bracket, nil]
  end

  def self.elapsed?(text)
    !text.empty? && text.chars.all? { |letter| ELAPSED_LETTERS.include?(letter) }
  end
  private_class_method :step, :close_or_extend, :elapsed?

  private

  def style_kinds(document)
    custom = custom_codes(document)
    cell_formats = child(document.root, 'cellXfs')
    return [] if cell_formats.nil?

    kinds = []
    cell_formats.each_element do |format|
      next unless format.name == 'xf'

      id = format.attributes['numFmtId'].to_i
      kinds << (custom.key?(id) ? self.class.kind_for_code(custom[id]) : BUILT_IN[id])
    end
    kinds
  end

  def custom_codes(document)
    codes = {}
    child(document.root, 'numFmts')&.each_element do |format|
      codes[format.attributes['numFmtId'].to_i] = format.attributes['formatCode'].to_s if format.name == 'numFmt'
    end
    codes
  end

  def child(element, name)
    return if element.nil?

    found = nil
    element.each_element { |item| found ||= item if item.name == name }
    found
  end
end
