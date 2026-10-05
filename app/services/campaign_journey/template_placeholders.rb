# Variables of a WhatsApp template body — positional ({{1}}) or named ({{nome}}) — read and filled
# by a plain left-to-right scan (String#index), no regular expressions (#1005 M1/B4).
# Filling is one pass: values are inserted literally, never scanned again (no chaining) and
# never read as back-references (\0, \&).
module CampaignJourney::TemplatePlaceholders
  OPEN = '{{'.freeze
  CLOSE = '}}'.freeze

  module_function

  # 'Olá {{1}}, vence {{ 2 }}' => ['1', '2'] (each once, in order; empty or unclosed ones ignored)
  def keys(text)
    tokens(text.to_s).filter_map { |token| token[:key] }.uniq
  end

  def render(text, values)
    tokens(text.to_s).map { |token| token[:key] && values.key?(token[:key]) ? values[token[:key]].to_s : token[:raw] }.join
  end

  # [{ raw: 'Olá ' }, { raw: '{{1}}', key: '1' }, ...]
  def tokens(text)
    result = []
    position = 0
    while (start = text.index(OPEN, position)) && (finish = text.index(CLOSE, start + OPEN.size))
      result << { raw: text[position...start] } if start > position
      raw = text[start...(finish + CLOSE.size)]
      result << { raw: raw, key: raw[OPEN.size...-CLOSE.size].strip.presence }
      position = finish + CLOSE.size
    end
    result << { raw: text[position..] } if position < text.size
    result
  end
end
