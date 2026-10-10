# Which comments of an ending tag's HTML survive the cleaning (#1104). The parser turns `<![CDATA[...]]>`, `<?...>`
# and other bogus markup into comments too, and Outlook reads conditional comments as markup, so a comment stays only
# when it is a plain note (no markup at all), an MSO conditional comment whose inner HTML passes HtmlCleaner
# unchanged, or one of the two halves of a downlevel-revealed condition (`<!--[if !mso]><!-->`, `<!--<![endif]-->`).
# CDATA never stays. String methods — no regex.
module EmailCampaigns::Ai::HtmlComment
  CDATA = '[CDATA['.freeze
  CONDITION = '[if'.freeze
  CONDITION_END = ']>'.freeze
  ENDIF = '<![endif]'.freeze
  REVEALED_END = '><!'.freeze

  module_function

  def keep?(content)
    text = content.to_s
    return false if text.lstrip.upcase.start_with?(CDATA)
    return true if text == ENDIF || revealed_open?(text)
    return conditional_safe?(text) if text.start_with?(CONDITION)

    markup_free?(text)
  end

  def markup_free?(text)
    text.exclude?('<') && text.exclude?('>')
  end

  def revealed_open?(text)
    text.start_with?(CONDITION) && text.end_with?(REVEALED_END) && text.count('<') == 1 && text.count('>') == 1
  end

  def conditional_safe?(text)
    close = text.index(CONDITION_END)
    return false if close.nil? || !text.end_with?(ENDIF) || !markup_free?(text[0...close])

    inner = text[(close + CONDITION_END.length)...(text.length - ENDIF.length)].to_s
    EmailCampaigns::Ai::HtmlCleaner.call(inner) == inner
  end
end
