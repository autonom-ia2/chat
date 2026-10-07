# Rewrites the merge tags of an imported model into ours (#1099), on the text nodes and attributes the parser already
# read — never on the raw markup. Fields go through MergeTags::Catalog; unsubscribe tags point at {{ unsubscribe_url }}
# in links and leave plain text (our locked footer brings the only link); platform-only links lose their anchor;
# conditionals keep their first branch (the others are recorded as dropped text); unknown tags become {{ key }} and are
# listed for the person to choose. A tag split across inline tags by an editor is joined back first. No regex.
class EmailCampaigns::Import::MergeTags
  LINK_ATTRIBUTES = %w[href].freeze
  TEXT_ATTRIBUTES = %w[src alt title].freeze
  UNSUBSCRIBE = '{{ unsubscribe_url }}'.freeze
  MAX_JOIN = 6
  INLINE = %w[span a strong b em i u font small sup sub mark].freeze

  def initialize(report)
    @report = report
    @stack = []
  end

  def apply(root)
    join_split_tags(root)
    root.css('[href]').each { |node| link(node) }
    root.css(TEXT_ATTRIBUTES.map { |name| "[#{name}]" }.join(', ')).each { |node| attributes(node) }
    root.xpath('.//text()').each { |node| text(node) }
    root
  end

  # A subject or title: fields stay, every other tag leaves.
  def plain_text(value)
    tokens = pair_names(Tokenizer.scan(value.to_s))
    tokens.map { |token| token.tag? ? kept_field(token) : token.raw }.join.split.join(' ')
  end

  # An attribute value with its tags rewritten; :platform_link when a link is nothing but a platform-only link.
  def attribute(value, link:)
    tokens = pair_names(Tokenizer.scan(value))
    parts = tokens.map do |token|
      next token.raw unless token.tag?

      resolution = Catalog.resolve(token)
      return :platform_link if link && resolution.kind == :platform_link && tokens.one?

      replacement(token, resolution, in_link: link)
    end
    parts.join
  end

  private

  def kept_field(token)
    resolution = Catalog.resolve(token)
    resolution.kind == :field ? "{{ #{resolution.key} }}" : ''
  end

  def link(node)
    value = node['href']
    return if Tokenizer.scan(value).none?(&:tag?)

    out = attribute(value, link: true)
    return node['href'] = out unless out == :platform_link

    @report.add(:platform_tags_removed)
    @report.drop_text(node.text, :platform_link)
    @report.drop_link(value, :platform_link)
    node.remove
  end

  def attributes(node)
    TEXT_ATTRIBUTES.each do |name|
      value = node[name]
      next if value.nil? || Tokenizer.scan(value).none?(&:tag?)

      out = attribute(value, link: false)
      node[name] = out == :platform_link ? '' : out
    end
  end

  def text(node)
    tokens = pair_names(Tokenizer.scan(node.content))
    return if tokens.none?(&:tag?) && @stack.empty?

    kept = +''
    tokens.each { |token| kept << piece(token) }
    node.content = kept
  end

  def piece(token)
    unless token.tag?
      return token.raw unless skipping?

      @report.drop_text(token.raw, :conditional)
      return ''
    end
    resolution = Catalog.resolve(token)
    return flow(resolution) if %i[open else close].include?(resolution.kind)
    return '' if skipping?

    replacement(token, resolution, in_link: false)
  end

  def flow(resolution)
    case resolution.kind
    when :open
      @stack.push(skipping? ? :skip : :keep)
      @report.add(:conditional_simplified)
    when :else then @stack[-1] = :skip if @stack.any?
    when :close then @stack.pop
    end
    ''
  end

  def skipping?
    @stack.include?(:skip)
  end

  def replacement(token, resolution, in_link:)
    case resolution.kind
    when :field then field(token, resolution)
    when :unsubscribe then in_link ? UNSUBSCRIBE : platform_noise
    when :unknown then unknown(token, resolution)
    else platform_noise
    end
  end

  def field(token, resolution)
    target = "{{ #{resolution.key} }}"
    @report.add(:tags_converted, item: { from: token.raw.strip, to: target }) unless token.raw.strip == target
    @report.add(:tag_simplified, item: token.raw.strip) if resolution.simplified
    target
  end

  def unknown(token, resolution)
    @report.add(:unknown_fields, item: { from: token.raw.strip, key: resolution.key })
    "{{ #{resolution.key} }}"
  end

  def platform_noise
    @report.add(:platform_tags_removed)
    ''
  end

  # *|FNAME|* *|LNAME|* is the full name.
  def pair_names(tokens)
    tokens.each_with_object([]) do |token, out|
      gap = out.last && !out.last.tag? && out.last.raw.strip.empty? ? 1 : 0
      first = out[-1 - gap]
      next out << token unless last_name?(token) && first_name?(first)

      out.pop(gap + 1)
      out << Tokenizer::Token.new("#{first.raw} #{token.raw}", :mustache, 'nome')
    end
  end

  def last_name?(token)
    token.syntax == :star_pipe && token.inner.strip.downcase == Catalog::LAST_NAME
  end

  def first_name?(token)
    token&.syntax == :star_pipe && token.inner.strip.downcase == Catalog::FIRST_NAME
  end

  # Joins "{{ " + "empresa }}" written by an editor in sibling inline tags of one block back into one text node.
  def join_split_tags(root)
    nodes = root.xpath('.//text()').to_a
    nodes.each_with_index do |node, index|
      next unless open_tag?(node.content)

      joined, used = join_from(node, nodes[(index + 1), MAX_JOIN].to_a)
      next if used.empty? || open_tag?(joined)

      node.content = joined
      used.each { |candidate| candidate.content = '' }
    end
  end

  def join_from(node, candidates)
    block = block_of(node)
    joined = node.content
    used = []
    candidates.each do |candidate|
      break unless block_of(candidate) == block

      joined += candidate.content
      used << candidate
      break unless open_tag?(joined)
    end
    [joined, used]
  end

  def block_of(node)
    node.ancestors.find { |ancestor| !ancestor.element? || INLINE.exclude?(ancestor.name) }
  end

  def open_tag?(text)
    Tokenizer::DELIMITERS.any? do |delimiter|
      next false if delimiter.open == delimiter.close

      start = text.rindex(delimiter.open)
      start && text.index(delimiter.close, start + delimiter.open.length).nil?
    end
  end
end
