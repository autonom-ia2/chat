# Splits text into plain runs and merge tags of the syntaxes e-mail platforms use (#1099): {{ }}, {{{ }}}, {% %},
# *| |*, [[ ]] and %% %%. A two-state machine (text / inside a tag) driven by String#index — no regex. An opener
# without its closer, or with a body longer than MAX_INNER, stays text, so prices like "50%" or a lone "{{" survive;
# %% %% only reads as a tag around a name (letters, digits, _ . : -), so "10%% hoje e 20%%" stays text too.
class EmailCampaigns::Import::MergeTags::Tokenizer
  Delimiter = Struct.new(:open, :close, :syntax)
  Token = Struct.new(:raw, :syntax, :inner) do
    def tag?
      !syntax.nil?
    end
  end

  DELIMITERS = [
    Delimiter.new('{{{', '}}}', :mustache), Delimiter.new('{{', '}}', :mustache), Delimiter.new('{%', '%}', :statement),
    Delimiter.new('*|', '|*', :star_pipe), Delimiter.new('[[', ']]', :double_bracket), Delimiter.new('%%', '%%', :percent)
  ].freeze
  OPEN_CHARS = DELIMITERS.map { |delimiter| delimiter.open[0] }.uniq.freeze
  MAX_INNER = 300
  NAME_CHARS = (('a'..'z').to_a + ('A'..'Z').to_a + ('0'..'9').to_a + %w[_ . : -]).freeze

  def self.scan(text)
    new(text.to_s).scan
  end

  def initialize(text)
    @text = text
  end

  def scan
    tokens = []
    plain = +''
    position = 0
    while position < @text.length
      tag = tag_at(position)
      if tag
        tokens << Token.new(plain, nil, nil) unless plain.empty?
        plain = +''
        tokens << tag
        position += tag.raw.length
      else
        following = next_candidate(position + 1)
        plain << @text[position...following]
        position = following
      end
    end
    tokens << Token.new(plain, nil, nil) unless plain.empty?
    tokens
  end

  private

  def tag_at(position)
    DELIMITERS.each do |delimiter|
      next unless @text[position, delimiter.open.length] == delimiter.open

      start = position + delimiter.open.length
      close = @text.index(delimiter.close, start)
      next unless close && inner?(delimiter, @text[start...close])

      return Token.new(@text[position...(close + delimiter.close.length)], delimiter.syntax, @text[start...close])
    end
    nil
  end

  def inner?(delimiter, inner)
    return false if inner.length > MAX_INNER || inner.strip.empty?

    delimiter.syntax != :percent || name?(inner)
  end

  def name?(inner)
    inner.each_char.all? { |char| NAME_CHARS.include?(char) }
  end

  # Next position where an opener could start; the text in between cannot hold a tag.
  def next_candidate(from)
    OPEN_CHARS.filter_map { |char| @text.index(char, from) }.min || @text.length
  end
end
