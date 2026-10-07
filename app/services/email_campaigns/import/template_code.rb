# Template code an imported model must not carry into ours (#1099). The sending worker renders the design with Liquid,
# so a statement ({% … %}) or an output tag other than one of our fields would run there — a loop of two billion turns,
# say — or break the send when left unclosed. MergeTags rewrites the tags it can read; what remains (a tag too long to
# read, an opener without its closer, one an editor split across inline tags that met again in the output) is taken out
# of the emitted MJML here, as the last step before our footer. Only our own form, {{ key }}, stays. A piece that spans
# markup loses just its opener, so no tag of the MJML is ever cut. Everything taken out is recorded. String#index — no regex.
module EmailCampaigns::Import::TemplateCode
  OUTPUT = ['{{', '}}'].freeze
  STATEMENT = ['{%', '%}'].freeze
  KEY_CHARS = EmailCampaigns::Import::MergeTags::Catalog::KEY_CHARS

  module_function

  def scrub(mjml, report)
    text = mjml.to_s
    memo = {}
    out = +''
    position = 0
    while (start = [OUTPUT.first, STATEMENT.first].filter_map { |opener| next_index(text, opener, position, memo) }.min)
      out << text[position...start]
      stop = piece_end(text, start, memo)
      field?(text[start...stop]) ? out << text[start...stop] : stop = drop(text, start, stop, report)
      position = stop
    end
    out << text[position..]
  end

  # Records the piece and returns where reading goes on: after it, or right after its opener when it spans markup.
  def drop(text, start, stop, report)
    stop = start + OUTPUT.first.length if text[start...stop].include?('<')
    report.drop_text(text[start...stop], :template)
    report.add(:template_code_removed)
    stop
  end

  # Where the piece starting at an opener ends: after its closer, or right after the opener when it has none.
  def piece_end(text, start, memo)
    open, close = text[start, STATEMENT.first.length] == STATEMENT.first ? STATEMENT : OUTPUT
    stop = next_index(text, close, start + open.length, memo)
    stop ? stop + close.length : start + open.length
  end

  # String#index remembered per needle, so a search never scans the same stretch twice (reads move forward only).
  def next_index(text, needle, from, memo)
    found = memo[needle]
    return if found == :none
    return found if found && found >= from

    memo[needle] = text.index(needle, from) || :none
    memo[needle] == :none ? nil : memo[needle]
  end

  # One of our fields: "{{ key }}" (or "{{key}}", as a link address keeps it), the key made of lowercase letters,
  # digits and underscores.
  def field?(tag)
    return false unless tag.start_with?(OUTPUT.first) && tag.end_with?(OUTPUT.last)

    key = tag[OUTPUT.first.length...-OUTPUT.last.length].strip
    key.present? && key.each_char.all? { |char| KEY_CHARS.include?(char) }
  end
end
