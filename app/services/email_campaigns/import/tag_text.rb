# Our merge tags inside a text (#1099, delivery C), read the same way QualityGate reads them: whatever sits between
# `{{` and the next `}}`, trimmed (and without a leading `-`). `keys` lists them; `replace` swaps every tag of one key
# for a replacement, leaving everything else as it was. String#index and slicing — no regex.
module EmailCampaigns::Import::TagText
  OPEN = '{{'.freeze
  CLOSE = '}}'.freeze

  module_function

  def keys(source)
    found = []
    each_tag(source.to_s) { |key, _raw| found << key }
    found
  end

  def replace(source, key, replacement)
    out = +''
    rest = each_tag(source.to_s) do |tag_key, raw, before|
      out << before << (tag_key == key ? replacement : raw)
    end
    out << rest
  end

  # Yields (key, raw tag, text before it) for each complete tag and returns what is left after the last one.
  def each_tag(source)
    rest = source
    while (start = rest.index(OPEN))
      stop = rest.index(CLOSE, start + OPEN.length)
      break if stop.nil?

      raw = rest[start...(stop + CLOSE.length)]
      yield(rest[(start + OPEN.length)...stop].strip.delete_prefix('-').strip, raw, rest[0...start])
      rest = rest[(stop + CLOSE.length)..]
    end
    rest
  end
end
