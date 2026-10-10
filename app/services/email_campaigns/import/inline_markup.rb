# Inline formatting the editor keeps inside mj-text (#1099): strong, em, links and spans carrying only what differs from
# the paragraph (color, size, weight, slant, decoration). Returns the opening and closing markup for one element.
module EmailCampaigns::Import::InlineMarkup
  STRONG = %w[strong b].freeze
  EMPHASIS = %w[em i].freeze
  UNDERLINE = %w[u ins].freeze
  STRIKE = %w[s strike del].freeze
  NONE = ['', ''].freeze
  WEIGHTS = { true => '700', false => '400' }.freeze
  SLANTS = { true => 'italic', false => 'normal' }.freeze

  module_function

  def wrap(element, own, parent)
    name = element.name
    return link(element, own) if name == 'a'
    return emphasis(STRONG.include?(name) ? %w[strong bold] : %w[em italic], own, parent) if (STRONG + EMPHASIS).include?(name)

    span(differences(element, own, parent))
  end

  # <strong> or <em>, unless the paragraph already has that weight or slant.
  def emphasis((tag, trait), own, parent)
    own.public_send(trait) && !parent.public_send(trait) ? ["<#{tag}>", "</#{tag}>"] : NONE
  end

  def link(element, own)
    href = element['href']
    return NONE if href.blank?

    decoration = decoration(element) || 'underline'
    [%(<a href="#{escape(href)}" style="#{escape("color:#{own.color};text-decoration:#{decoration}")}">), '</a>']
  end

  def differences(element, own, parent)
    out = {
      'color' => (own.color if own.color != parent.color),
      'font-size' => ("#{own.font_size.round}px" if own.font_size.round != parent.font_size.round),
      'text-decoration' => decoration(element)
    }
    out.merge(slant_and_weight(own, parent)).compact
  end

  def slant_and_weight(own, parent)
    {
      'font-weight' => (WEIGHTS[own.bold] unless own.bold == parent.bold),
      'font-style' => (SLANTS[own.italic] unless own.italic == parent.italic)
    }
  end

  def decoration(element)
    return 'underline' if UNDERLINE.include?(element.name)
    return 'line-through' if STRIKE.include?(element.name)

    value = EmailCampaigns::Import::StyleMap.plain(EmailCampaigns::Import::StyleMap.parse(element['style'])['text-decoration']).downcase
    value.split.find { |part| %w[underline line-through none].include?(part) }
  end

  def span(declarations)
    return NONE if declarations.empty?

    [%(<span style="#{escape(EmailCampaigns::Import::StyleMap.dump(declarations))}">), '</span>']
  end

  def escape(value)
    value.to_s.gsub('&', '&amp;').gsub('"', '&quot;').gsub('<', '&lt;')
  end
end
